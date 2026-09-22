--- Input buffer: a normal Neovim buffer used as the prompt editor.
---
--- Multi-line is supported: `<CR>` in insert mode inserts a newline, while
--- `<C-s>` sends. In normal mode `<CR>` sends. This avoids `vim.fn.input` and
--- keeps the editor fully in the buffer.
local M = {}

local Input = {}
Input.__index = Input
M.Input = Input

--- @param opts table?
--- @param opts.on_submit fun(text: string)
--- @param opts.height integer? Split height (default 6).
--- @return table input
function M.new(opts)
  opts = opts or {}
  return setmetatable({
    buf = nil,
    win = nil,
    height = opts.height or 6,
    on_submit = opts.on_submit or function() end,
  }, Input)
end

--- @return integer bufnr
function Input:ensure_buffer()
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    return self.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, ("pi://input/%d"):format(buf))
  vim.bo[buf].filetype = "pi-input"
  vim.bo[buf].bufhidden = "hide"
  self.buf = buf
  return buf
end

--- Attach the input buffer to a window and install keymaps/options.
---
--- @param win integer
function Input:attach_window(win)
  local buf = self:ensure_buffer()
  self.win = win
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].number = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = true
  vim.wo[win].winfixheight = true
  self:_map_keys(buf)
end

--- @param buf integer
function Input:_map_keys(buf)
  local function submit()
    self:submit()
  end
  vim.keymap.set("n", "<CR>", submit, { buffer = buf, desc = "pi: send prompt" })
  vim.keymap.set("n", "<C-s>", submit, { buffer = buf, desc = "pi: send prompt" })
  vim.keymap.set("i", "<C-s>", submit, { buffer = buf, desc = "pi: send prompt" })
  vim.keymap.set("i", "<C-c>", "<Esc>", { buffer = buf, desc = "pi: leave insert" })
end

--- Read the current text, clear the buffer, restore insert mode, and submit.
---
--- @return string|nil text The submitted text, or nil if empty.
function Input:submit()
  local buf = self.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  while #lines > 1 and lines[#lines] == "" do
    table.remove(lines)
  end
  local text = table.concat(lines, "\n")
  if text:match("^%s*$") then
    return nil
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_set_cursor(self.win, { 1, 0 })
    if vim.api.nvim_get_current_win() == self.win then
      vim.cmd("startinsert!")
    end
  end

  self.on_submit(text)
  return text
end

return M
