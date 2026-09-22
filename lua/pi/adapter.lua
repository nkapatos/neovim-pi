--- Pi RPC transport: subprocess + strict JSONL framing + id correlation.
---
--- This module owns the wire transport. Everything it emits toward the UI is a
--- unified event (see `pi.protocol`); it never leaks raw Pi RPC.
---
--- Framing note: Pi requires LF (`\n`) as the only record delimiter and forbids
--- treating U+2028/U+2029 as separators. We therefore consume raw byte chunks
--- from `vim.system` (never line-buffered output) and split on `\n` ourselves.
local protocol = require("pi.protocol")

local M = {}

--- Split an accumulated buffer plus a new chunk into complete LF-delimited
--- records. Strips a single trailing `\r` (CRLF) from each record. Does *not*
--- treat U+2028/U+2029 or any other code point as a delimiter.
---
--- @param buffer string Already-buffered, not-yet-terminated bytes.
--- @param chunk string? Newly received bytes (may be nil at EOF).
--- @return string[] records
--- @return string rest Incomplete trailing bytes to retain.
function M.feed(buffer, chunk)
  local data = buffer .. (chunk or "")
  local records = {}
  local pos = 1
  while true do
    local nl = data:find("\n", pos, true)
    if not nl then
      break
    end
    local record = data:sub(pos, nl - 1)
    if record:sub(-1) == "\r" then
      record = record:sub(1, -2)
    end
    records[#records + 1] = record
    pos = nl + 1
  end
  return records, data:sub(pos)
end

--- Encode one command as a single JSONL line.
---
--- @param obj table
--- @return string
function M.encode(obj)
  return vim.json.encode(obj) .. "\n"
end

local Adapter = {}
Adapter.__index = Adapter
M.Adapter = Adapter

--- @param opts table
--- @param opts.cmd string[]? Defaults to `{ "pi", "--mode", "rpc" }`.
--- @param opts.cwd string?
--- @param opts.env table?
--- @param opts.on_event fun(event: table)
--- @param opts.on_exit fun(code: integer, signal: integer)?
--- @return table adapter
function M.new(opts)
  opts = opts or {}
  return setmetatable({
    cmd = opts.cmd or { "pi", "--mode", "rpc" },
    cwd = opts.cwd,
    env = opts.env,
    on_event = opts.on_event or function() end,
    on_exit = opts.on_exit,
    _obj = nil,
    _rx = "",
    _drain_scheduled = false,
    _pending = {},
    _next_id = 0,
    _kill_timer = nil,
  }, Adapter)
end

--- Spawn the Pi child process and begin reading.
---
--- @return boolean ok
--- @return string|nil error
function Adapter:start()
  if self._obj then
    return true
  end

  local ok, obj = pcall(vim.system, self.cmd, {
    stdin = true,
    text = false,
    cwd = self.cwd,
    env = self.env,
    stdout = function(err, data)
      self:_on_stdout(err, data)
    end,
    stderr = function(err, data)
      self:_on_stderr(err, data)
    end,
  }, function(res)
    self:_on_exit(res)
  end)

  if not ok then
    local message = tostring(obj)
    self:_emit({
      type = protocol.EVENT.STATUS,
      level = "error",
      message = "failed to start pi: " .. message,
    })
    self:_emit({ type = protocol.EVENT.EXIT, code = -1, signal = 0 })
    return false, message
  end

  self._obj = obj
  self:_emit({ type = protocol.EVENT.READY, cmd = self.cmd })
  return true
end

--- Whether the child process is currently running.
---
--- @return boolean
function Adapter:is_running()
  return self._obj ~= nil
end

--- Send a fire-and-forget command.
---
--- @param command table
--- @return boolean sent
function Adapter:send(command)
  local ok = self:_write(command)
  return ok
end

--- Send a command and invoke `callback(data, error, response)` on its response.
--- The callback receives the response payload, not the wire envelope.
---
--- @param command table
--- @param callback fun(data: any, error: string|nil, response: table)
--- @return string|nil id
function Adapter:request(command, callback)
  local ok, obj = self:_write(command, callback)
  if not ok then
    return nil
  end
  return obj.id
end

--- Abort the current operation.
---
--- @param callback fun(data: any, error: string|nil, response: table)?
function Adapter:abort(callback)
  return self:request(protocol.command(protocol.OP.ABORT), callback or function() end)
end

--- Close stdin (EOF) so Pi shuts down, escalating to SIGTERM after a grace
--- period. `on_exit` fires when the process actually exits.
function Adapter:stop()
  if not self._obj then
    return
  end
  pcall(self._obj.write, self._obj, nil)
  if not self._kill_timer then
    self._kill_timer = vim.defer_fn(function()
      self._kill_timer = nil
      if self._obj then
        pcall(self._obj.kill, self._obj, "sigterm")
      end
    end, 3000)
  end
end

--- Immediately signal the child process.
---
--- @param signal string|integer?
function Adapter:kill(signal)
  if self._obj then
    pcall(self._obj.kill, self._obj, signal or "sigterm")
  end
end

-- Internals ------------------------------------------------------------------

function Adapter:_next_request_id()
  self._next_id = self._next_id + 1
  return ("nvim-pi-%d"):format(self._next_id)
end

--- @param obj table
--- @param callback fun(data: any, error: string|nil, response: table)?
--- @return boolean ok
--- @return table obj The (possibly id-augmented) command object.
function Adapter:_write(obj, callback)
  if not self._obj then
    return false, obj
  end
  if callback then
    if obj.id == nil then
      obj = vim.tbl_extend("force", obj, { id = self:_next_request_id() })
    end
    self._pending[obj.id] = callback
  end
  local ok = pcall(self._obj.write, self._obj, M.encode(obj))
  if not ok then
    if obj.id ~= nil then
      self._pending[obj.id] = nil
    end
    return false, obj
  end
  return true, obj
end

--- Fast-event callback: accumulate raw bytes and schedule parsing in the main
--- loop (`vim.system` stdout runs in a fast-event context, where most APIs are
--- unavailable).
---
--- @param _err string|nil
--- @param data string|nil
function Adapter:_on_stdout(_err, data)
  if data then
    self._rx = self._rx .. data
  end
  if self._drain_scheduled then
    return
  end
  self._drain_scheduled = true
  vim.schedule(function()
    self._drain_scheduled = false
    self:_consume("")
  end)
end

function Adapter:_on_stderr(_err, data)
  if not data or data == "" then
    return
  end
  vim.schedule(function()
    self:_emit({
      type = protocol.EVENT.STATUS,
      level = "warn",
      message = ("pi stderr: %s"):format(vim.trim(data)),
    })
  end)
end

--- Frame and dispatch accumulated output. Pure enough to drive from tests.
---
--- @param chunk string?
function Adapter:_consume(chunk)
  local records
  records, self._rx = M.feed(self._rx, chunk)
  for _, line in ipairs(records) do
    self:_dispatch_line(line)
  end
end

--- @param line string
function Adapter:_dispatch_line(line)
  if line == "" then
    return
  end

  local ok, wire = pcall(vim.json.decode, line)
  if not ok or type(wire) ~= "table" then
    self:_emit({
      type = protocol.EVENT.STATUS,
      level = "error",
      message = "invalid JSON from pi: " .. line:sub(1, 200),
    })
    return
  end

  if wire.type == "response" then
    self:_resolve(wire)
    return
  end

  local event = protocol.translate_event(wire)
  if event then
    self:_emit(event)
  end
end

--- @param wire table
function Adapter:_resolve(wire)
  local id = wire.id
  if id ~= nil and self._pending[id] then
    local callback = self._pending[id]
    self._pending[id] = nil
    local err = nil
    if not wire.success then
      err = wire.error or "command failed"
    end
    callback(wire.data, err, wire)
    return
  end

  if not wire.success then
    self:_emit({
      type = protocol.EVENT.STATUS,
      level = "error",
      message = wire.error or ("command failed: %s"):format(tostring(wire.command)),
    })
  end
end

--- @param res table
function Adapter:_on_exit(res)
  local code, signal = res.code or 0, res.signal or 0
  vim.schedule(function()
    self._obj = nil
    self._pending = {}
    if self._kill_timer then
      pcall(self._kill_timer.stop, self._kill_timer)
      pcall(self._kill_timer.close, self._kill_timer)
      self._kill_timer = nil
    end
    self:_emit({ type = protocol.EVENT.EXIT, code = code, signal = signal })
    if self.on_exit then
      self.on_exit(code, signal)
    end
  end)
end

--- @param event table
function Adapter:_emit(event)
  self.on_event(event)
end

return M
