-- neovim-pi: Neovim as the TUI for the Pi coding-agent harness.
--
-- Package entry point. Deliberately tiny and defensive: its only job is to
-- fail loudly (not crash) on unsupported Neovim versions, then hand off to
-- `lua/pi/init.lua`.

if vim.g.loaded_neovim_pi == 1 then
  return
end
vim.g.loaded_neovim_pi = 1

local ok, pi = pcall(require, "pi")
if not ok then
  vim.api.nvim_echo({
    { ("neovim-pi: failed to load module `pi`: %s"):format(tostring(pi)), "ErrorMsg" },
  }, true, {})
  return
end

local supported, current = pi.is_supported()
if not supported then
  vim.api.nvim_echo({
    {
      ("neovim-pi: unsupported Neovim %s (requires >= %s); plugin disabled."):format(
        current,
        pi.MIN_NVIM
      ),
      "ErrorMsg",
    },
  }, true, {})
  return
end

pi.setup()

vim.api.nvim_create_user_command("Pi", function()
  require("pi").open()
end, { desc = "pi: open the chat session (starting Pi if needed)" })

vim.api.nvim_create_user_command("PiSend", function(args)
  require("pi").prompt(args.args)
end, { nargs = "+", desc = "pi: send a prompt to the running agent" })

vim.api.nvim_create_user_command("PiAbort", function()
  require("pi").abort()
end, { desc = "pi: abort the current operation" })

vim.api.nvim_create_user_command("PiModel", function()
  require("pi").select_model()
end, { desc = "pi: pick a model" })

vim.api.nvim_create_user_command("PiStop", function()
  require("pi").stop()
end, { desc = "pi: stop the Pi process" })

vim.api.nvim_create_user_command("PiStatus", function()
  local pi_mod = require("pi")
  vim.notify(pi_mod.status() .. "\n" .. pi_mod.session_status(), vim.log.levels.INFO)
end, { desc = "pi: show plugin and session status" })
