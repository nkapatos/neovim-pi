--- Streaming chat buffer rendering.
---
--- Deltas are coalesced and flushed on `vim.schedule`, so a burst of streaming
--- events results in a single buffer update. Blocks are highlighted by kind
--- (assistant text, thinking, tool calls) via extmarks over the appended range.
local protocol = require("pi.protocol")

local M = {}

--- Namespace for chat highlight extmarks.
M.ns = vim.api.nvim_create_namespace("pi.chat")

local Chat = {}
Chat.__index = Chat
M.Chat = Chat

--- Define the plugin's highlight groups (non-destructive defaults).
function M.setup_highlights()
  local function link(name, to)
    vim.api.nvim_set_hl(0, name, { link = to, default = true })
  end
  link("PiText", "Normal")
  link("PiThinking", "Comment")
  link("PiTool", "Function")
  link("PiToolOk", "DiagnosticOk")
  link("PiToolError", "DiagnosticError")
  link("PiUser", "Title")
  link("PiError", "ErrorMsg")
end

--- Append `text` to the end of `buf`, continuing the last line if needed.
---
--- @param buf integer
--- @param text string
local function append_text(buf, text)
  local parts = vim.split(text, "\n", { plain = true })
  local count = vim.api.nvim_buf_line_count(buf)
  local last = vim.api.nvim_buf_get_lines(buf, count - 1, count, false)[1] or ""

  if count == 1 and last == "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, parts)
  else
    parts[1] = last .. parts[1]
    vim.api.nvim_buf_set_lines(buf, count - 1, count, false, parts)
  end
end

--- Extract plain text from a message content field (string or block array).
---
--- @param content string|table|nil
--- @return string
local function text_of(content)
  if type(content) == "string" then
    return content
  end
  if type(content) == "table" then
    local parts = {}
    for _, block in ipairs(content) do
      if block.type == "text" then
        parts[#parts + 1] = block.text or ""
      end
    end
    return table.concat(parts, "\n")
  end
  return ""
end

--- Apply a highlight extmark over a buffer range.
---
--- @param buf integer
--- @param start_row integer
--- @param start_col integer
--- @param end_row integer
--- @param end_col integer
--- @param hl string
local function highlight(buf, start_row, start_col, end_row, end_col, hl)
  if start_row == end_row and end_col <= start_col then
    return
  end
  pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, start_row, start_col, {
    end_row = end_row,
    end_col = end_col,
    hl_group = hl,
    priority = 100,
  })
end

--- @param opts table?
--- @return table chat
function M.new(opts)
  opts = opts or {}
  return setmetatable({
    buf = nil,
    on_abort = opts.on_abort or function() end,
    _pending = "",
    _pending_hl = nil,
    _flush_scheduled = false,
  }, Chat)
end

--- @return integer bufnr
function Chat:ensure_buffer()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    return self.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, ("pi://chat/%d"):format(buf))
  vim.bo[buf].filetype = "pi-chat"
  vim.bo[buf].bufhidden = "hide"
  self.buf = buf
  return buf
end

--- Show the chat buffer in the current window and install buffer-local keys.
---
--- @return integer bufnr
function Chat:open()
  local buf = self:ensure_buffer()
  vim.api.nvim_win_set_buf(0, buf)
  self:_map_keys(buf)
  self:_scroll_to_end()
  return buf
end

--- @param buf integer
function Chat:_map_keys(buf)
  vim.keymap.set("n", "<Esc>", function()
    self.on_abort()
  end, { buffer = buf, desc = "pi: abort current operation" })
end

--- Handle one unified event.
---
--- @param event table
function Chat:on_event(event)
  local kind = event.type
  if kind == protocol.EVENT.TEXT_DELTA then
    self:_push(event.text or "", "PiText")
  elseif kind == protocol.EVENT.THINKING_DELTA then
    self:_push(event.text or "", "PiThinking")
  elseif kind == protocol.EVENT.TOOL_START then
    self:_push(("\n▸ %s\n"):format(event.name or "tool"), "PiTool")
  elseif kind == protocol.EVENT.TOOL_END then
    local mark = event.is_error and "✗" or "✓"
    self:_push(
      ("  %s %s\n"):format(mark, event.name or "tool"),
      event.is_error and "PiToolError" or "PiToolOk"
    )
  elseif kind == protocol.EVENT.TURN_END then
    self:_ensure_newline()
  elseif kind == protocol.EVENT.SETTLED then
    self:_ensure_newline()
  elseif kind == protocol.EVENT.READY then
    self:_push("pi session attached\n", "PiTool")
  elseif kind == protocol.EVENT.EXIT then
    self:_push(("\n[pi exited: code=%s signal=%s]\n"):format(event.code, event.signal), "PiError")
  elseif kind == protocol.EVENT.STATUS then
    vim.notify(
      event.message or "pi status",
      event.level == "error" and vim.log.levels.ERROR or vim.log.levels.WARN
    )
  end
end

--- Echo a user prompt into the transcript.
---
--- @param text string
function Chat:message(text)
  self:_ensure_newline()
  self:_push(("› %s\n"):format(text), "PiUser")
end

--- Whether the transcript currently ends on a fresh line.
---
--- @return boolean
function Chat:_ends_with_newline()
  if self._pending ~= "" then
    return self._pending:sub(-1) == "\n"
  end
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    return true
  end
  local count = vim.api.nvim_buf_line_count(self.buf)
  local last = vim.api.nvim_buf_get_lines(self.buf, count - 1, count, false)[1]
  return last == nil or last == ""
end

function Chat:_ensure_newline()
  if not self:_ends_with_newline() then
    self:_push("\n", nil)
  end
end

--- Queue text (with an optional highlight group) and schedule a coalesced flush.
---
--- @param text string
--- @param hl string|nil
function Chat:_push(text, hl)
  if text == nil or text == "" then
    return
  end
  if self._pending ~= "" and self._pending_hl ~= hl then
    self:_flush()
  end
  self._pending = self._pending .. text
  self._pending_hl = hl
  if self._flush_scheduled then
    return
  end
  self._flush_scheduled = true
  vim.schedule(function()
    self._flush_scheduled = false
    self:_flush()
  end)
end

function Chat:_flush()
  local text = self._pending
  local hl = self._pending_hl
  self._pending = ""
  self._pending_hl = nil
  if text == "" then
    return
  end

  local buf = self:ensure_buffer()
  local before = vim.api.nvim_buf_line_count(buf)
  local last = vim.api.nvim_buf_get_lines(buf, before - 1, before, false)[1] or ""
  local start_row, start_col = before - 1, #last

  append_text(buf, text)

  if hl then
    local after = vim.api.nvim_buf_line_count(buf)
    local end_row = after - 1
    local end_line = vim.api.nvim_buf_get_lines(buf, end_row, end_row + 1, false)[1] or ""
    highlight(buf, start_row, start_col, end_row, #end_line, hl)
  end

  self:_scroll_to_end()
end

function Chat:_scroll_to_end()
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    return
  end
  for _, win in ipairs(vim.fn.win_findbuf(self.buf)) do
    if vim.api.nvim_win_is_valid(win) then
      local last = vim.api.nvim_buf_line_count(self.buf)
      pcall(vim.api.nvim_win_set_cursor, win, { last, 0 })
    end
  end
end

--- Clear the transcript buffer.
function Chat:clear()
  self._pending = ""
  self._pending_hl = nil
  local buf = self:ensure_buffer()
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  self:_scroll_to_end()
end

--- Replace the transcript with a full message history (used by resume/fork).
---
--- @param messages table[]
function Chat:render_messages(messages)
  self:clear()
  for _, message in ipairs(messages or {}) do
    self:_render_message(message)
  end
  self:_flush()
  self:_scroll_to_end()
end

--- @param message table
function Chat:_render_message(message)
  local role = message.role
  if role == "user" then
    self:message(text_of(message.content))
  elseif role == "assistant" then
    for _, block in ipairs(message.content or {}) do
      if block.type == "text" then
        self:_push(block.text or "", "PiText")
      elseif block.type == "thinking" then
        self:_push(block.thinking or "", "PiThinking")
      elseif block.type == "toolCall" then
        self:_push(("\n▸ %s\n"):format(block.name or "tool"), "PiTool")
      end
    end
    self:_ensure_newline()
  elseif role == "toolResult" then
    local mark = message.isError and "✗" or "✓"
    self:_push(
      ("  %s %s\n"):format(mark, message.toolName or "tool"),
      message.isError and "PiToolError" or "PiToolOk"
    )
  elseif role == "bashExecution" then
    self:_push(("$ %s\n%s\n"):format(message.command or "", message.output or ""), "PiTool")
  end
end

return M
