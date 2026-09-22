local adapter_mod = require("pi.adapter")
local protocol = require("pi.protocol")

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
end)
