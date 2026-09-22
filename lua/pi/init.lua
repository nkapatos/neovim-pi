--- neovim-pi: module entry point.
---
--- This is the public Lua surface of the plugin. Iteration 0 only provides the
--- version guard, setup, and status helpers. The adapter and UI are added in
--- later iterations.
local M = {}

--- Minimum supported Neovim version.
M.MIN_NVIM = "0.12.5"

--- Runtime configuration. Populated by `setup()`.
M.config = {
  --- Default launch spec for `:Pi` / `:PiStart` (see `pi.launch`).
  launch = {
    session = "new",
    approve = "default",
  },
  --- Override the LSP-style project-root markers (defaults in `pi.launch`).
  root_markers = nil,
}

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

--- Merge the configured launch spec with per-call overrides.
--- @param launch_opts table|nil
--- @return table
local function resolve_launch(launch_opts)
  return vim.tbl_deep_extend("force", {}, M.config.launch or {}, launch_opts or {})
end

--- Describe what `:Pi` would launch right now (no process started).
--- @param opts table?
--- @return table { spec, cwd, argv, command, trust }
function M.describe_launch(opts)
  opts = opts or {}
  local launch = require("pi.launch")
  local spec = resolve_launch(opts.launch)
  local cwd = opts.cwd or launch.root(opts.buf or 0, M.config.root_markers)
  return {
    spec = spec,
    cwd = cwd,
    argv = launch.argv(spec),
    command = launch.describe(spec),
    trust = launch.trust(spec, cwd),
  }
end

--- Open the chat session, starting Pi if needed.
--- @param opts table?
--- @return table
function M.open(opts)
  opts = vim.tbl_extend("force", opts or {}, { launch = resolve_launch((opts or {}).launch) })
  return require("pi.session").open(opts)
end

--- Start a Pi session without focusing the buffer.
--- @param opts table?
--- @return table state
--- @return string|nil error
function M.start(opts)
  opts = vim.tbl_extend("force", opts or {}, { launch = resolve_launch((opts or {}).launch) })
  return require("pi.session").start(opts)
end

--- Stop any running session and start a fresh one with the given spec.
--- @param opts table?
--- @return table
function M.restart(opts)
  opts = vim.tbl_extend("force", opts or {}, { launch = resolve_launch((opts or {}).launch) })
  return require("pi.session").restart(opts)
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
  return require("pi.session").statusline()
end

--- Pick a model via `vim.ui.select` and switch the running session to it.
function M.select_model()
  return require("pi.session").select_model()
end

--- Refresh cached session state (model, thinking level, ...).
--- @param callback fun(data: table|nil, err: string|nil)?
function M.refresh_state(callback)
  return require("pi.session").refresh_state(callback)
end

--- One-line session status (for statuslines).
--- @return string
function M.statusline()
  return require("pi.session").statusline()
end

--- Resolved cwd / command / trust of the running session (nil when stopped).
--- @return string|nil cwd
--- @return string|nil command
--- @return table|nil trust
function M.session_launch_info()
  local session = require("pi.session")
  return session.cwd(), session.command(), session.trust()
end

--- Start a fresh session in the running process and reload the transcript.
function M.new_session()
  return require("pi.session").new_session()
end

--- Resume a session by explicit path and reload the transcript.
--- @param path string
function M.resume(path)
  return require("pi.session").resume(path)
end

--- Fork at an explicit entry id and reload the transcript.
--- @param entry_id string
function M.fork(entry_id)
  return require("pi.session").fork(entry_id)
end

--- Reload the transcript from Pi's message history.
--- @param callback fun(data: table|nil, err: string|nil)?
function M.refresh_transcript(callback)
  return require("pi.session").refresh_transcript(callback)
end

--- Sequential `vim.ui` questionnaire helper.
local function ask(spec, questions, index, done)
  if index > #questions then
    return done(spec)
  end
  local question = questions[index]
  local function next_step(value)
    if value == nil then
      return done(nil)
    end
    spec[question.field] = value
    ask(spec, questions, index + 1, done)
  end
  if question.kind == "select" then
    vim.ui.select(question.options, { prompt = question.prompt }, next_step)
  else
    vim.ui.input({ prompt = question.prompt, default = spec[question.field] or "" }, function(value)
      if value == nil then
        return done(nil)
      end
      spec[question.field] = value ~= "" and value or nil
      ask(spec, questions, index + 1, done)
    end)
  end
end

--- Interactive launch builder: prompt for session/trust/model/tools/name, show
--- the resolved command + cwd + trust, and start on confirmation.
function M.start_dialog()
  local launch = require("pi.launch")
  local spec = vim.deepcopy(M.config.launch or {})
  local cwd = launch.root(0, M.config.root_markers)

  local questions = {
    {
      kind = "select",
      field = "session",
      prompt = "Session",
      options = { "new", "continue", "resume", "none" },
    },
    {
      kind = "select",
      field = "approve",
      prompt = "Project trust",
      options = { "default", "approve", "no-approve" },
    },
    { kind = "input", field = "model", prompt = "Model (blank = default): " },
    {
      kind = "input",
      field = "tools",
      prompt = "Tools allowlist, comma-separated (blank = all): ",
    },
    { kind = "input", field = "name", prompt = "Session name (blank = none): " },
  }

  ask(spec, questions, 1, function(final)
    if not final then
      return
    end
    local trust = launch.trust(final, cwd)
    local message = ("Start?\ncwd: %s\n%s\nproject-local resources: %s\ntrust: %s"):format(
      cwd,
      launch.describe(final),
      trust.project_resources and "present" or "none",
      trust.description
    )
    if vim.fn.confirm(message, "&Start\n&Cancel", 1) ~= 1 then
      return
    end
    M.restart({ launch = final, cwd = cwd })
  end)
end

return M
