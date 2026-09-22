--- Launch spec: project-root resolution and `pi` argv construction.
---
--- Iteration 3 goal: starting from nvim must be equivalent to typing the
--- matching `pi …` command in the resolved project root. This module is pure
--- (no process spawning) so it is fully unit-testable.
local M = {}

--- Markers used LSP-style to find the project root.
M.DEFAULT_ROOT_MARKERS = {
  ".git",
  ".hg",
  ".pi",
  "package.json",
  "pyproject.toml",
  "Cargo.toml",
  "go.mod",
  "Makefile",
}

--- Resolve the project root for a buffer or path using markers.
---
--- @param source integer|string|nil Buffer number (default 0) or path.
--- @param markers string[]|nil
--- @return string
function M.root(source, markers)
  markers = markers or M.DEFAULT_ROOT_MARKERS
  source = source or 0

  local name
  if type(source) == "number" then
    name = vim.api.nvim_buf_get_name(source)
  else
    name = source
  end

  local start = (name ~= nil and name ~= "") and name or vim.fn.getcwd()
  local root = vim.fs.root(start, markers)
  if root then
    return root
  end
  if name ~= nil and name ~= "" then
    return vim.fn.fnamemodify(name, ":p:h")
  end
  return vim.fn.getcwd()
end

--- @param argv string[]
--- @param flag string
--- @param value string|boolean|nil
local function push_flag(argv, flag, value)
  if value == nil or value == "" then
    return
  end
  argv[#argv + 1] = flag
  if value ~= true then
    argv[#argv + 1] = value
  end
end

--- @param argv string[]
--- @param flag string
--- @param value string|string[]|nil
local function push_list(argv, flag, value)
  if value == nil then
    return
  end
  if type(value) == "table" then
    if #value == 0 then
      return
    end
    value = table.concat(value, ",")
  end
  push_flag(argv, flag, value)
end

--- Build the `pi --mode rpc` argv from a launch spec.
---
--- Supported spec fields: `executable`, `provider`, `model`, `thinking`,
--- `session` (`"new"|"continue"|"resume"|"none"|<path>`), `session_dir`, `name`,
--- `tools`, `exclude_tools`, `no_tools`, `no_builtin_tools`, `no_extensions`,
--- `extensions`, `no_skills`, `no_context_files`, `approve`
--- (`"default"|"approve"|"no-approve"`), and `extra` (raw args).
---
--- @param spec table|nil
--- @return string[]
function M.argv(spec)
  spec = spec or {}
  local argv = { spec.executable or "pi", "--mode", "rpc" }

  push_flag(argv, "--provider", spec.provider)
  push_flag(argv, "--model", spec.model)
  push_flag(argv, "--thinking", spec.thinking)

  if spec.session == "none" then
    push_flag(argv, "--no-session", true)
  elseif spec.session == "continue" then
    push_flag(argv, "--continue", true)
  elseif spec.session == "resume" then
    push_flag(argv, "--resume", true)
  elseif type(spec.session) == "string" and spec.session ~= "" and spec.session ~= "new" then
    push_flag(argv, "--session", spec.session)
  end
  push_flag(argv, "--session-dir", spec.session_dir)
  push_flag(argv, "--name", spec.name)

  push_list(argv, "--tools", spec.tools)
  push_list(argv, "--exclude-tools", spec.exclude_tools)
  if spec.no_tools then
    push_flag(argv, "--no-tools", true)
  end
  if spec.no_builtin_tools then
    push_flag(argv, "--no-builtin-tools", true)
  end

  if spec.no_extensions then
    push_flag(argv, "--no-extensions", true)
  end
  if type(spec.extensions) == "table" then
    for _, ext in ipairs(spec.extensions) do
      push_flag(argv, "--extension", ext)
    end
  elseif type(spec.extensions) == "string" then
    push_flag(argv, "--extension", spec.extensions)
  end
  if spec.no_skills then
    push_flag(argv, "--no-skills", true)
  end
  if spec.no_context_files then
    push_flag(argv, "--no-context-files", true)
  end

  if spec.approve == "approve" then
    push_flag(argv, "--approve", true)
  elseif spec.approve == "no-approve" then
    push_flag(argv, "--no-approve", true)
  end

  if type(spec.extra) == "table" then
    for _, arg in ipairs(spec.extra) do
      argv[#argv + 1] = arg
    end
  end

  return argv
end

--- Quote a single argv element only when the shell needs it.
---
--- @param arg string
--- @return string
local function shell_arg(arg)
  if arg:match("^[%w_%-%./:=@%%+,]+$") then
    return arg
  end
  return vim.fn.shellescape(arg)
end

--- Human-readable, shell-quoted command line for the spec.
---
--- @param spec table|nil
--- @return string
function M.describe(spec)
  local parts = {}
  for _, arg in ipairs(M.argv(spec)) do
    parts[#parts + 1] = shell_arg(arg)
  end
  return table.concat(parts, " ")
end

--- Whether the project root has project-local Pi resources gated by trust.
---
--- @param root string|nil
--- @return boolean
function M.project_has_resources(root)
  if not root or root == "" then
    return false
  end
  if vim.fn.isdirectory(root .. "/.pi") == 1 then
    return true
  end
  if vim.fn.isdirectory(root .. "/.agents/skills") == 1 then
    return true
  end
  return vim.fn.filereadable(root .. "/.pi/settings.json") == 1
end

--- Describe the effective project-trust state for a spec and project root.
---
--- RPC mode never prompts: without `-a`/`-na`, Pi silently applies the global
--- `defaultProjectTrust` setting. This reports what nvim asked for plus whether
--- the project actually has resources that the decision affects.
---
--- @param spec table|nil
--- @param root string|nil
--- @return table
function M.trust(spec, root)
  spec = spec or {}
  local mode = spec.approve or "default"
  local description
  if mode == "approve" then
    description = "trusted for this run (--approve)"
  elseif mode == "no-approve" then
    description = "ignored for this run (--no-approve)"
  else
    description = "from Pi's global defaultProjectTrust (RPC applies it silently)"
  end
  return {
    mode = mode,
    description = description,
    project_resources = M.project_has_resources(root),
  }
end

return M
