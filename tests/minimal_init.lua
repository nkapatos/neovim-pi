-- Minimal init for the plenary test run.
--
-- `PlenaryBustedDirectory` launches each spec in a child Neovim with `-u`
-- pointing here, so this file (not the parent's runtimepath) must expose the
-- plugin and plenary.

local this = debug.getinfo(1, "S").source:sub(2)
local tests_dir = vim.fn.fnamemodify(this, ":p:h")
local root = vim.fn.fnamemodify(tests_dir, ":h")

vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(root .. "/.deps/plenary.nvim")
