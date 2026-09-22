--- neovim-pi: module entry point.
---
--- This is the public Lua surface of the plugin. Iteration 0 only provides the
--- version guard, setup, and status helpers. The adapter and UI are added in
--- later iterations.
local M = {}

--- Minimum supported Neovim version.
M.MIN_NVIM = "0.12.5"

--- Runtime configuration. Populated by `setup()`.
M.config = {}

--- Whether the experimental `ui2` module was successfully enabled.
M.ui2_enabled = false

--- Parse a `MAJOR.MINOR.PATCH` version string.
---
--- @param version string
--- @return integer[]|nil # {major, minor, patch}, or nil if unparseable
function M.parse_version(version)
  local major, minor, patch = tostring(version):match("^(%d+)%.(%d+)%.(%d+)")
  if not major then
    return nil
  end
  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

--- True if version `a` is strictly older than version `b`.
---
--- @param a string
--- @param b string
--- @return boolean
function M.version_lt(a, b)
  local va, vb = M.parse_version(a), M.parse_version(b)
  if not va or not vb then
    return false
  end
  for i = 1, 3 do
    if va[i] ~= vb[i] then
      return va[i] < vb[i]
    end
  end
  return false
end

--- Best-effort current Neovim version as `MAJOR.MINOR.PATCH`.
---
--- @return string
function M.current_version()
  local ok, version = pcall(vim.version)
  if ok and type(version) == "table" and version.major then
    return ("%d.%d.%d"):format(version.major, version.minor, version.patch)
  end

  local ok_exec, out = pcall(vim.fn.execute, "version")
  if ok_exec then
    local found = out:match("NVIM v(%d+%.%d+%.%d+)")
    if found then
      return found
    end
  end

  return "unknown"
end

--- Whether the running Neovim satisfies `M.MIN_NVIM`.
---
--- @return boolean supported
--- @return string current
function M.is_supported()
  local current = M.current_version()
  if current == "unknown" then
    -- `has()` is authoritative for exact `nvim-x.y.z` feature checks.
    return vim.fn.has("nvim-" .. M.MIN_NVIM) == 1, current
  end
  return not M.version_lt(current, M.MIN_NVIM), current
end

--- Initialize the plugin. Safe to call more than once.
---
--- @param opts table|nil
--- @return table M
function M.setup(opts)
  if M._setup_done then
    return M
  end
  M._setup_done = true
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  M.ui2_enabled = require("pi.ui2").enable()

  return M
end

--- Human-readable status line for `:Pi`.
---
--- @return string
function M.status()
  local supported, current = M.is_supported()
  return ("neovim-pi — Neovim %s (supported: %s), ui2: %s"):format(
    current,
    supported and "yes" or "no",
    M.ui2_enabled and "enabled" or "disabled"
  )
end

--- Open the chat session, starting Pi if needed.
--- @param opts table?
--- @return table
function M.open(opts)
  return require("pi.session").open(opts)
end

--- Start a Pi session without focusing the buffer.
--- @param opts table?
--- @return table state
--- @return string|nil error
function M.start(opts)
  return require("pi.session").start(opts)
end

--- Send a prompt to the running agent.
--- @param text string
function M.prompt(text)
  return require("pi.session").prompt(text)
end

--- Abort the current operation.
function M.abort()
  return require("pi.session").abort()
end

--- Stop the Pi process.
function M.stop()
  return require("pi.session").stop()
end

--- Status of the current session.
--- @return string
function M.session_status()
  return require("pi.session").status()
end

return M
