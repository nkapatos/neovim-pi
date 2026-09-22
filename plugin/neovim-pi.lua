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
  vim.notify(require("pi").status(), vim.log.levels.INFO)
end, { desc = "neovim-pi: show plugin status (placeholder)" })
