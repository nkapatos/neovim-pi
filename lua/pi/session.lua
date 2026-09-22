--- Session wiring: one adapter + one chat buffer + one input buffer.
---
--- Per the architecture, one Neovim instance maps to one Pi RPC process and one
--- Pi session. This module is the thin glue between the transport and the UI.
local adapter = require("pi.adapter")
local protocol = require("pi.protocol")
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
    vim.wo[state.chat_win].statusline = " " .. M.statusline() .. " "
  end
  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    vim.wo[state.input_win].statusline = " pi input   <C-s> send · <Esc><CR> send · <C-c> normal "
  end
end

--- Build the split layout if it is missing: chat on top, input below.
local function ensure_layout()
  local chat_buf = state.chat:ensure_buffer()

  if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
    render_statusline()
    vim.api.nvim_set_current_win(state.input_win)
    vim.cmd("startinsert!")
    return
  end

  vim.api.nvim_win_set_buf(0, chat_buf)
  state.chat_win = vim.api.nvim_get_current_win()
  vim.wo[state.chat_win].number = false
  vim.wo[state.chat_win].signcolumn = "no"
  vim.wo[state.chat_win].wrap = true

  vim.cmd(("botright %dsplit"):format(state.input.height))
  state.input_win = vim.api.nvim_get_current_win()
  state.input:attach_window(state.input_win)

  render_statusline()
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
    cmd = opts.cmd,
    cwd = opts.cwd or vim.fn.getcwd(),
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
  if state.chat then
    state.chat:on_event(event)
  end
  if event.type == protocol.EVENT.SETTLED then
    M.refresh_state()
  end
  render_statusline()
end

return M
