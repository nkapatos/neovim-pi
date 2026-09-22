--- Minimal streaming chat buffer for Iteration 1.
---
--- Deltas are coalesced and flushed on `vim.schedule`, so a burst of streaming
--- events results in a single buffer update. This is deliberately small; the
--- full chat UX arrives in Iteration 2.
local protocol = require("pi.protocol")

local M = {}

local Chat = {}
Chat.__index = Chat
M.Chat = Chat

--- @return table chat
function M.new()
  return setmetatable({
    buf = nil,
    on_abort = function() end,
    _pending = "",
    _flush_scheduled = false,
  }, Chat)
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

--- @return integer bufnr
function Chat:ensure_buffer()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    return self.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, ("pi://%d"):format(buf))
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
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "pi: close chat window" })
end

--- Handle one unified event.
---
--- @param event table
function Chat:on_event(event)
  local kind = event.type
  if kind == protocol.EVENT.TEXT_DELTA then
    self:_push(event.text or "")
  elseif kind == protocol.EVENT.THINKING_DELTA then
    self:_push(event.text or "")
  elseif kind == protocol.EVENT.TOOL_START then
    self:_push(("\n\n[%s]\n"):format(event.name or "tool"))
  elseif kind == protocol.EVENT.TOOL_END then
    self:_push(("\n[%s %s]\n"):format(event.name or "tool", event.is_error and "failed" or "done"))
  elseif kind == protocol.EVENT.SETTLED then
    self:_push("\n")
  elseif kind == protocol.EVENT.READY then
    self:_push("pi session attached\n")
  elseif kind == protocol.EVENT.EXIT then
    self:_push(("\n[pi exited: code=%s signal=%s]\n"):format(event.code, event.signal))
  elseif kind == protocol.EVENT.STATUS then
    vim.notify(
      event.message or "pi status",
      event.level == "error" and vim.log.levels.ERROR or vim.log.levels.WARN
    )
  end
end

--- Queue text and schedule a coalesced flush.
---
--- @param text string
function Chat:_push(text)
  if text == "" then
    return
  end
  self._pending = self._pending .. text
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
  self._pending = ""
  if text == "" then
    return
  end
  local buf = self:ensure_buffer()
  append_text(buf, text)
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

return M
