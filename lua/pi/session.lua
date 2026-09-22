--- Session wiring: one adapter + one chat buffer for one Pi session.
---
--- Per the architecture, one Neovim instance maps to one Pi RPC process and one
--- Pi session. This module is the thin glue between the transport and the UI.
local adapter = require("pi.adapter")
local protocol = require("pi.protocol")
local chat = require("pi.ui.chat")

local M = {}

local state = {
  adapter = nil,
  chat = nil,
  streaming = false,
  exit_code = nil,
}

local function ensure_cleanup_autocmd()
  local group = vim.api.nvim_create_augroup("neovim_pi_session", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if state.adapter then
        state.adapter:kill("sigterm")
      end
    end,
    desc = "neovim-pi: terminate the Pi child process",
  })
end

--- @return boolean
function M.is_active()
  return state.adapter ~= nil and state.adapter:is_running()
end

--- Start a session if none is running and open the chat buffer.
---
--- @param opts table?
--- @return table state
--- @return string|nil error
function M.start(opts)
  opts = opts or {}
  if M.is_active() then
    return state
  end

  state.exit_code = nil
  state.streaming = false
  state.chat = chat.new()
  state.chat.on_abort = function()
    M.abort()
  end

  state.adapter = adapter.new({
    cmd = opts.cmd,
    cwd = opts.cwd or vim.fn.getcwd(),
    env = opts.env,
    on_event = function(event)
      M._on_event(event)
    end,
  })

  ensure_cleanup_autocmd()
  state.chat:open()

  local ok, err = state.adapter:start()
  if not ok then
    return state, err
  end
  return state
end

--- Focus the chat buffer, starting a session if necessary.
---
--- @return table state
function M.open()
  if not state.chat or not (state.chat.buf and vim.api.nvim_buf_is_valid(state.chat.buf)) then
    return M.start()
  end
  state.chat:open()
  return state
end

--- Send a prompt to the agent.
---
--- @param text string
function M.prompt(text)
  if type(text) ~= "string" or text == "" then
    return
  end
  if not M.is_active() then
    local _, err = M.start()
    if not M.is_active() then
      vim.notify("pi: not running" .. (err and (": " .. err) or ""), vim.log.levels.ERROR)
      return
    end
  end

  state.chat:_push(("\n\n> %s\n\n"):format(text))
  state.streaming = true
  state.adapter:request(protocol.command(protocol.OP.PROMPT, { message = text }), function(_, err)
    if err then
      state.streaming = false
      vim.notify("pi: prompt failed: " .. err, vim.log.levels.ERROR)
    end
  end)
end

--- Abort the current operation.
function M.abort()
  if not M.is_active() then
    return
  end
  state.adapter:abort(function(_, err)
    if err then
      vim.notify("pi: abort failed: " .. err, vim.log.levels.ERROR)
    end
  end)
end

--- Stop the session (close stdin; escalate to SIGTERM after a grace period).
function M.stop()
  if state.adapter then
    state.adapter:stop()
  end
end

--- @return string
function M.status()
  if M.is_active() then
    return ("pi: running (streaming=%s)"):format(state.streaming and "yes" or "no")
  end
  return ("pi: stopped (exit=%s)"):format(tostring(state.exit_code))
end

--- @param event table
function M._on_event(event)
  if event.type == protocol.EVENT.SETTLED or event.type == protocol.EVENT.EXIT then
    state.streaming = false
  end
  if event.type == protocol.EVENT.EXIT then
    state.exit_code = event.code
  end
  if state.chat then
    state.chat:on_event(event)
  end
end

return M
