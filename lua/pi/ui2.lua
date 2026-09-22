--- Experimental `ui2` (messages/cmdline redesign) support.
---
--- `vim._core.ui2` is experimental and may be missing or renamed. Everything
--- here is guarded so the plugin degrades to the legacy UI instead of
--- erroring.
local M = {}

--- Whether the experimental ui2 module can be used.
---
--- @return boolean available
--- @return string|nil reason
function M.is_available()
  local ok, ui2 = pcall(require, "vim._core.ui2")
  if not ok then
    return false, "module `vim._core.ui2` not found"
  end
  if type(ui2) ~= "table" or type(ui2.enable) ~= "function" then
    return false, "`vim._core.ui2.enable` is not a function"
  end
  return true, nil
end

--- Enable ui2, if available.
---
--- @param opts table|nil Options forwarded to `ui2.enable()`.
--- @return boolean enabled
--- @return string|nil reason
function M.enable(opts)
  local available, reason = M.is_available()
  if not available then
    return false, reason
  end

  local ok, err = pcall(require("vim._core.ui2").enable, opts)
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

return M
