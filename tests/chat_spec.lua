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
      return lines:find("✓ bash", 1, true) ~= nil and lines:find("code=0", 1, true) ~= nil
    end)
    local text = table.concat(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false), "\n")
    assert.matches("▸ bash", text)
    assert.matches("✓ bash", text)
    assert.matches("pi exited: code=0", text)
  end)

  it("echoes user messages and highlights distinct blocks", function()
    local c = chat.new()
    c:message("do the thing")
    c:on_event({ type = protocol.EVENT.THINKING_DELTA, text = "hmm" })
    c:on_event({ type = protocol.EVENT.TEXT_DELTA, text = "done" })

    wait_for(function()
      local lines = c.buf and table.concat(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false), "\n")
        or ""
      return lines:find("done", 1, true) ~= nil
    end)
    local text = table.concat(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false), "\n")
    assert.matches("› do the thing", text)
    assert.matches("hmm", text)
    assert.matches("done", text)

    local marks = vim.api.nvim_buf_get_extmarks(c.buf, require("pi.ui.chat").ns, 0, -1, {})
    assert.is_true(#marks > 0)
  end)

  it("renders a resumed transcript from messages", function()
    local c = chat.new()
    c:render_messages({
      { role = "user", content = "hi" },
      {
        role = "assistant",
        content = {
          { type = "thinking", thinking = "hmm" },
          { type = "text", text = "hello" },
          { type = "toolCall", id = "t1", name = "bash" },
        },
      },
      { role = "toolResult", toolName = "bash", isError = false, content = {} },
      { role = "bashExecution", command = "ls", output = "a" },
    })

    local text = table.concat(vim.api.nvim_buf_get_lines(c.buf, 0, -1, false), "\n")
    assert.matches("› hi", text)
    assert.matches("hmm", text)
    assert.matches("hello", text)
    assert.matches("▸ bash", text)
    assert.matches("✓ bash", text)
    assert.matches("%$ ls", text)
  end)
end)
