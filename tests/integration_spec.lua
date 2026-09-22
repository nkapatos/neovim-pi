local adapter_mod = require("pi.adapter")
local protocol = require("pi.protocol")

--- Locate Pi's bundled rpc-demo example extension (version-agnostic).
---
--- @return string|nil
local function find_rpc_demo()
  local exe = vim.fn.exepath("pi")
  if exe == "" then
    return nil
  end
  local node_modules = vim.fn.fnamemodify(vim.fn.fnamemodify(exe, ":p:h"), ":h")
  local pattern = node_modules
    .. "/.mise/*/node_modules/@earendil-works/pi-coding-agent/examples/extensions/rpc-demo.ts"
  return vim.fn.glob(pattern, false, true)[1]
end

--- Integration coverage against a real `pi --mode rpc` process. Skipped when
--- `pi` is not on PATH.
describe("pi.adapter integration", function()
  if vim.fn.executable("pi") ~= 1 then
    it("SKIP: pi executable not found on PATH", function()
      pending("pi not installed")
    end)
    return
  end

  it("spawns pi --mode rpc and handles responses, then shuts down cleanly", function()
    local a = adapter_mod.new({
      cmd = { "pi", "--mode", "rpc", "--no-session" },
      cwd = vim.fn.getcwd(),
      on_event = function() end,
    })

    local ok, err = a:start()
    assert.is_true(ok, err)
    assert.is_true(a:is_running())

    local state
    a:request(protocol.command("get_state"), function(data, e)
      state = { data = data, err = e }
    end)
    vim.wait(30000, function()
      return state ~= nil
    end, 50)
    assert.is_truthy(state, "no get_state response from pi")
    assert.is_nil(state.err)
    assert.is_false(state.data.isStreaming)

    local new_session
    a:request(protocol.command("new_session"), function(data, e)
      new_session = { data = data, err = e }
    end)
    vim.wait(30000, function()
      return new_session ~= nil
    end, 50)
    assert.is_truthy(new_session, "no new_session response from pi")
    assert.is_nil(new_session.err)

    local messages
    a:request(protocol.command("get_messages"), function(data, e)
      messages = { data = data, err = e }
    end)
    vim.wait(30000, function()
      return messages ~= nil
    end, 50)
    assert.is_truthy(messages, "no get_messages response from pi")
    assert.is_nil(messages.err)
    assert.is_true(type(messages.data.messages) == "table")

    local models
    a:request(protocol.command("get_available_models"), function(data, e)
      models = { data = data, err = e }
    end)
    vim.wait(30000, function()
      return models ~= nil
    end, 50)
    assert.is_truthy(models, "no get_available_models response from pi")
    assert.is_nil(models.err)
    assert.is_true(#models.data.models > 0)

    local first = models.data.models[1]
    local set_model
    a:request(
      protocol.command("set_model", { provider = first.provider, model_id = first.id }),
      function(data, e)
        set_model = { data = data, err = e }
      end
    )
    vim.wait(30000, function()
      return set_model ~= nil
    end, 50)
    assert.is_truthy(set_model, "no set_model response from pi")
    assert.is_nil(set_model.err)

    a:stop()
    vim.wait(15000, function()
      return not a:is_running()
    end, 50)
    assert.is_false(a:is_running(), "pi did not exit after stop()")
  end)

  it("wires a session into a chat buffer and stops cleanly", function()
    local session = require("pi.session")
    local state = session.start({
      cmd = { "pi", "--mode", "rpc", "--no-session" },
      cwd = vim.fn.getcwd(),
    })
    assert.is_truthy(state.chat)
    assert.is_true(session.is_active())

    vim.wait(20000, function()
      local buf = state.chat.buf
      if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return false
      end
      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      return text:find("pi session attached", 1, true) ~= nil
    end, 50)

    session.stop()
    vim.wait(15000, function()
      return not session.is_active()
    end, 50)
    assert.is_false(session.is_active(), "session did not stop cleanly")
  end)

  it("starts from a launch spec and exposes cwd/command", function()
    local session = require("pi.session")
    local state = session.start({
      launch = { session = "none", model = "deepseek/deepseek-flash" },
      cwd = vim.fn.getcwd(),
    })
    assert.is_true(state ~= nil)
    assert.is_true(session.is_active())
    assert.equal(vim.fn.getcwd(), session.cwd())

    local command = session.command()
    assert.is_truthy(command)
    assert.matches("%-%-mode rpc", command)
    assert.matches("%-%-no%-session", command)
    assert.matches("deepseek/deepseek%-flash", command)

    session.stop()
    vim.wait(15000, function()
      return not session.is_active()
    end, 50)
    assert.is_false(session.is_active())
  end)

  it("answers an extension dialog end-to-end (rpc-demo)", function()
    local rpc_demo = find_rpc_demo()
    if not rpc_demo then
      pending("rpc-demo example extension not found")
      return
    end

    local events = {}
    local a = adapter_mod.new({
      cmd = { "pi", "--mode", "rpc", "--no-session", "-e", rpc_demo },
      cwd = vim.fn.getcwd(),
      on_event = function(event)
        events[#events + 1] = event
      end,
    })
    assert.is_true(a:start())

    local function find_ui(method)
      for _, event in ipairs(events) do
        if event.type == protocol.EVENT.UI_REQUEST and event.request.method == method then
          return event.request
        end
      end
      return nil
    end

    -- session_start emits fire-and-forget setTitle/setWidget.
    vim.wait(30000, function()
      return find_ui("setWidget") ~= nil or find_ui("setTitle") ~= nil
    end, 50)
    assert.is_truthy(find_ui("setWidget") or find_ui("setTitle"), "no session_start UI request")

    -- The /rpc-input command opens an input dialog.
    a:request(protocol.command("prompt", { message = "/rpc-input" }), function() end)
    vim.wait(30000, function()
      return find_ui("input") ~= nil
    end, 50)
    local dialog = find_ui("input")
    assert.is_truthy(dialog, "no input dialog request")

    -- Answer it; the extension then notifies with the entered value.
    a:send(protocol.command("ui_response", { id = dialog.id, value = "hello" }))
    vim.wait(30000, function()
      local notify = find_ui("notify")
      return notify ~= nil and (notify.message or ""):find("hello", 1, true) ~= nil
    end, 50)
    assert.is_truthy(find_ui("notify"), "no notify after answering the input dialog")

    a:stop()
    vim.wait(15000, function()
      return not a:is_running()
    end, 50)
    assert.is_false(a:is_running())
  end)
end)
