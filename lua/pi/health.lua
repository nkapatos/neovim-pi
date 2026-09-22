--- `:checkhealth neovim-pi`
local M = {}

function M.check()
  local pi = require("pi")

  vim.health.start("neovim-pi")

  local supported, current = pi.is_supported()
  if supported then
    vim.health.ok(("Neovim %s (>= %s required)"):format(current, pi.MIN_NVIM))
  else
    vim.health.error(("Neovim %s is unsupported"):format(current), {
      ("Install Neovim >= %s"):format(pi.MIN_NVIM),
    })
  end

  local available, reason = require("pi.ui2").is_available()
  if available then
    vim.health.ok("Experimental ui2 (messages/cmdline) is available")
  else
    vim.health.warn("Experimental ui2 unavailable; using legacy messages/cmdline", { reason })
  end

  if vim.fn.executable("pi") == 1 then
    vim.health.ok("`pi` executable found on PATH")
  else
    vim.health.error("`pi` executable not found on PATH", {
      "Install the Pi coding agent and ensure `pi` is on PATH",
    })
  end
end

return M
