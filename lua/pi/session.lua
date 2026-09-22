--- Session wiring: one adapter + one chat buffer + one input buffer.
---
--- Per the architecture, one Neovim instance maps to one Pi RPC process and one
--- Pi session. This module is the thin glue between the transport and the UI.
local adapter = require("pi.adapter")
local protocol = require("pi.protocol")
local launch = require("pi.launch")
local chat = require("pi.ui.chat")
local input = require("pi.ui.input")

local M = {}

local state = {
  adapter = nil,
  chat = nil,
  input = nil,
  chat_win = nil,
  input_win = nil,
  streaming = false,
  exit_code = nil,
  info = nil,
  spec = nil,
  cwd = nil,
  cmd = nil,
  ext_status = {},
  widgets = {},
}

local function ensure_cleanup_autocmd()
  local group = vim.api.nvim_create_augroup("neovim_pi_session", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if state.adapter then
        state.adapter:kill("sigterm")
      end
    end,
    desc = "neovim-pi: terminate the Pi child process",
  })
end

local function render_statusline()
  if state.chat_win and vim.api.nvim_win_is_valid(state.chat_win) then
    local extra = {}
    for _, text in pairs(state.ext_status or {}) do
      if text and text ~= "" then
        extra[#extra + 1] = text
      end
    end
    local suffix = #extra > 0 and ("  ·  " .. table.concat(extra, " · ")) or ""
    vim.wo[state.chat_win].statusline = " " .. M.statusline() .. suffix .. " "
  end
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    local widget = {}
    for _, lines in pairs(state.widgets or {}) do
      for _, line in ipairs(lines or {}) do
        widget[#widget + 1] = line
      end
    end
    vim.wo[state.input_win].winbar = #widget > 0 and (" " .. table.concat(widget, "  ·  ") .. " ")
      or ""
    vim.wo[state.input_win].statusline = " pi input   <C-s> send · <Esc><CR> send · <C-c> normal "
  end
end

--- Route one `extension_ui_request` to the extension-UI renderer.
---
--- @param request table
local function handle_ui_request(request)
  require("pi.ui.extension").handle(request, {
    respond = function(response)
      if state.adapter then
        state.adapter:send(protocol.command(protocol.OP.RESPOND_UI, response))
      end
    end,
    notify = function(message, level)
      vim.notify(message, level)
    end,
    set_status = function(key, text)
      state.ext_status[key] = text
      render_statusline()
    end,
    set_widget = function(key, lines)
      state.widgets[key] = lines
      render_statusline()
    end,
    set_title = function(title)
      pcall(vim.fn.settitle, title)
    end,
    set_editor_text = function(text)
      if not state.input then
        return
      end
      local buf = state.input:ensure_buffer()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text or "", "\n", { plain = true }))
      if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
        vim.api.nvim_set_current_win(state.input_win)
        vim.cmd("startinsert!")
      end
    end,
  })
end

--- Build the split layout if it is missing: chat on top, input below.
local function ensure_layout()
  local chat_buf = state.chat:ensure_buffer()

  if not (state.chat_win and vim.api.nvim_win_is_valid(state.chat_win)) then
    if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
      vim.api.nvim_set_current_win(state.input_win)
      vim.cmd("aboveleft split")
    end
    state.chat_win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_win_set_buf(state.chat_win, chat_buf)
  vim.wo[state.chat_win].number = false
  vim.wo[state.chat_win].signcolumn = "no"
  vim.wo[state.chat_win].wrap = true

  if not (state.input_win and vim.api.nvim_win_is_valid(state.input_win)) then
    vim.api.nvim_set_current_win(state.chat_win)
    vim.cmd(("botright %dsplit"):format(state.input.height))
    state.input_win = vim.api.nvim_get_current_win()
  end
  state.input:attach_window(state.input_win)

  render_statusline()
  vim.api.nvim_set_current_win(state.input_win)
  vim.cmd("startinsert!")
end

--- @return boolean
function M.is_active()
  return state.adapter ~= nil and state.adapter:is_running()
end

--- Start a session if none is running. Does not move focus.
---
--- @param opts table?
--- @return table state
--- @return string|nil error
function M.start(opts)
  opts = opts or {}
  if M.is_active() then
    return state
  end

  state.exit_code = nil
  state.streaming = false
  state.info = nil
  state.ext_status = {}
  state.widgets = {}

  state.spec = opts.launch or { session = "new" }
  state.cwd = opts.cwd or launch.root(opts.buf or 0, opts.root_markers)
  state.cmd = opts.cmd or launch.argv(state.spec)

  chat.setup_highlights()

  state.chat = chat.new()
  state.chat.on_abort = function()
    M.abort()
  end
  state.input = input.new({
    on_submit = function(text)
      M.prompt(text)
    end,
  })

  state.adapter = adapter.new({
    cmd = state.cmd,
    cwd = state.cwd,
    env = opts.env,
    on_event = function(event)
      M._on_event(event)
    end,
  })

  ensure_cleanup_autocmd()

  local ok, err = state.adapter:start()
  if ok then
    M.refresh_state()
  end
  return state, err
end

--- Open (or focus) the chat + input layout, starting a session if needed.
---
--- @param opts table?
--- @return table state
function M.open(opts)
  if not M.is_active() then
    local _, err = M.start(opts)
    if not M.is_active() then
      vim.notify("pi: not running" .. (err and (": " .. err) or ""), vim.log.levels.ERROR)
      return state
    end
  end
  ensure_layout()
  return state
end

--- Stop any running session, then start and focus a new one.
---
--- @param opts table?
--- @return table state
function M.restart(opts)
  if M.is_active() then
    M.stop()
    vim.wait(5000, function()
      return not M.is_active()
    end, 50)
  end
  return M.open(opts)
end

--- Send a prompt to the agent.
---
--- @param text string
function M.prompt(text)
  if type(text) ~= "string" or text:match("^%s*$") then
    return
  end
  if not M.is_active() then
    M.start()
    if not M.is_active() then
      vim.notify("pi: not running", vim.log.levels.ERROR)
      return
    end
  end

  state.chat:message(text)
  state.streaming = true
  render_statusline()

  state.adapter:request(protocol.command(protocol.OP.PROMPT, { message = text }), function(_, err)
    if err then
      state.streaming = false
      render_statusline()
      vim.notify("pi: prompt failed: " .. err, vim.log.levels.ERROR)
    end
  end)
end

--- Abort the current operation.
function M.abort()
  if not M.is_active() then
    return
  end
  state.adapter:abort(function(_, err)
    if err then
      vim.notify("pi: abort failed: " .. err, vim.log.levels.ERROR)
    end
  end)
end

--- Stop the session (close stdin; escalate to SIGTERM after a grace period).
function M.stop()
  if state.adapter then
    state.adapter:stop()
  end
end

--- Refresh the cached session state from Pi (model, thinking level, ...).
---
--- @param callback fun(data: table|nil, err: string|nil)?
function M.refresh_state(callback)
  if not M.is_active() then
    return
  end
  state.adapter:request(protocol.command(protocol.OP.GET_STATE), function(data, err)
    if not err and data then
      state.info = data
    end
    render_statusline()
    if callback then
      callback(data, err)
    end
  end)
end

--- Replace the transcript from Pi's message history (resume/fork/new).
---
--- @param callback fun(data: table|nil, err: string|nil)?
function M.refresh_transcript(callback)
  if not M.is_active() then
    return
  end
  state.adapter:request(protocol.command(protocol.OP.GET_MESSAGES), function(data, err)
    if err then
      vim.notify("pi: get_messages failed: " .. err, vim.log.levels.ERROR)
      return
    end
    state.chat:render_messages((data and data.messages) or {})
    if callback then
      callback(data, err)
    end
  end)
end

--- Start a fresh session (same process) and reload the transcript.
function M.new_session()
  if not M.is_active() then
    return
  end
  state.adapter:request(protocol.command(protocol.OP.NEW_SESSION), function(_, err)
    if err then
      vim.notify("pi: new_session failed: " .. err, vim.log.levels.ERROR)
      return
    end
    M.refresh_transcript()
    M.refresh_state()
  end)
end

--- Resume a session by explicit path, then reload the transcript.
---
--- @param path string
function M.resume(path)
  if not M.is_active() then
    vim.notify("pi: not running", vim.log.levels.WARN)
    return
  end
  state.adapter:request(
    protocol.command(protocol.OP.SWITCH_SESSION, { session_path = path }),
    function(data, err)
      if err then
        vim.notify("pi: switch_session failed: " .. err, vim.log.levels.ERROR)
        return
      end
      if data and data.cancelled then
        vim.notify("pi: switch cancelled by extension", vim.log.levels.WARN)
        return
      end
      M.refresh_transcript()
      M.refresh_state()
      vim.notify("pi: resumed " .. path, vim.log.levels.INFO)
    end
  )
end

--- Fork at an explicit entry id, then reload the transcript.
---
--- @param entry_id string
function M.fork(entry_id)
  if not M.is_active() then
    vim.notify("pi: not running", vim.log.levels.WARN)
    return
  end
  state.adapter:request(
    protocol.command(protocol.OP.FORK, { entry_id = entry_id }),
    function(data, err)
      if err then
        vim.notify("pi: fork failed: " .. err, vim.log.levels.ERROR)
        return
      end
      if data and data.cancelled then
        vim.notify("pi: fork cancelled by extension", vim.log.levels.WARN)
        return
      end
      M.refresh_transcript()
      M.refresh_state()
    end
  )
end

--- Pick a model with `vim.ui.select` and switch to it.
function M.select_model()
  if not M.is_active() then
    vim.notify("pi: not running", vim.log.levels.WARN)
    return
  end

  state.adapter:request(protocol.command(protocol.OP.GET_AVAILABLE_MODELS), function(data, err)
    if err then
      vim.notify("pi: could not list models: " .. err, vim.log.levels.ERROR)
      return
    end
    local models = (data and data.models) or {}
    if #models == 0 then
      vim.notify("pi: no models available", vim.log.levels.WARN)
      return
    end

    vim.ui.select(models, {
      prompt = "Select model",
      format_item = function(m)
        return ("%s (%s)"):format(m.name or m.id, m.provider or "?")
      end,
    }, function(choice)
      if not choice then
        return
      end
      state.adapter:request(
        protocol.command(protocol.OP.SET_MODEL, {
          provider = choice.provider,
          model_id = choice.id,
        }),
        function(_, set_err)
          if set_err then
            vim.notify("pi: set_model failed: " .. set_err, vim.log.levels.ERROR)
          else
            vim.notify("pi: model set to " .. (choice.name or choice.id), vim.log.levels.INFO)
            M.refresh_state()
          end
        end
      )
    end)
  end)
end

--- @return string|nil Launch cwd of the running session.
function M.cwd()
  return state.cwd
end

--- @return string|nil Shell-quoted command line of the running session.
function M.command()
  if not state.spec then
    return nil
  end
  return launch.describe(state.spec)
end

--- @return table|nil Launch spec of the running session.
function M.launch_spec()
  return state.spec
end

--- @return table|nil Effective project-trust description for the session.
function M.trust()
  if not state.spec then
    return nil
  end
  return launch.trust(state.spec, state.cwd)
end

--- @return string
function M.statusline()
  if not M.is_active() then
    return "pi: stopped"
  end
  local info = state.info or {}
  local model = info.model and (info.model.name or info.model.id) or "…"
  local thinking = info.thinkingLevel or "-"
  local status = state.streaming and "streaming" or "idle"
  return ("pi: %s · %s · %s"):format(model, thinking, status)
end

--- @param event table
function M._on_event(event)
  if event.type == protocol.EVENT.SETTLED or event.type == protocol.EVENT.EXIT then
    state.streaming = false
  end
  if event.type == protocol.EVENT.EXIT then
    state.exit_code = event.code
  end
  if event.type == protocol.EVENT.UI_REQUEST then
    handle_ui_request(event.request)
  end
  if state.chat then
    state.chat:on_event(event)
  end
  if event.type == protocol.EVENT.SETTLED then
    M.refresh_state()
  end
  render_statusline()
end

return M
