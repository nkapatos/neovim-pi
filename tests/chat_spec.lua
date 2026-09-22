local chat = require("pi.ui.chat")
local protocol = require("pi.protocol")

--- Wait until `predicate` is true, pumping the event loop (flushes are
--- scheduled).
local function wait_for(predicate)
  vim.wait(1000, predicate, 20)
end

describe("pi.ui.chat buffer streaming", function()
  it("appends streamed text deltas into one line", function()
    local c = chat.new()
    c:on_event({ type = protocol.EVENT.TEXT_DELTA, text = "Hello" })
    c:on_event({ type = protocol.EVENT.TEXT_DELTA, text = " world" })

    wait_for(function()
      return c.buf ~= nil and vim.api.nvim_buf_get_lines(c.buf, 0, 1, false)[1] == "Hello world"
    end)
    assert.equal("Hello world", vim.api.nvim_buf_get_lines(c.buf, 0, 1, false)[1])
  end)

  it("continues the last line across flushes and handles embedded newlines", function()
    local c = chat.new()
    c:on_event({ type = protocol.EVENT.TEXT_DELTA, text = "a\nb" })
    wait_for(function()
      return c.buf ~= nil and vim.api.nvim_buf_line_count(c.buf) == 2
    end)

    c:on_event({ type = protocol.EVENT.TEXT_DELTA, text = "c\n" })
    c:on_event({ type = protocol.EVENT.TEXT_DELTA, text = "d" })

    wait_for(function()
      local lines = c.buf and vim.api.nvim_buf_get_lines(c.buf, 0, -1, false) or {}
      return #lines == 3 and lines[3] == "d"
    end)
    assert.same({ "a", "bc", "d" }, vim.api.nvim_buf_get_lines(c.buf, 0, -1, false))
  end)

  it("renders tool lifecycle and exit markers", function()
    local c = chat.new()
    c:on_event({ type = protocol.EVENT.TOOL_START, name = "bash" })
    c:on_event({ type = protocol.EVENT.TOOL_END, name = "bash", is_error = false })
    c:on_event({ type = protocol.EVENT.EXIT, code = 0, signal = 0 })

    wait_for(function()
      local lines = c.buf and table.concat(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false), "\n")
        or ""
      return lines:find("[bash done]", 1, true) ~= nil and lines:find("code=0", 1, true) ~= nil
    end)
    local text = table.concat(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false), "\n")
    assert.matches("%[bash%]", text)
    assert.matches("%[bash done%]", text)
    assert.matches("pi exited: code=0", text)
  end)
end)
