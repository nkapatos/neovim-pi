local input = require("pi.ui.input")

describe("pi.ui.input", function()
  it("submits text, joins lines, and clears the buffer", function()
    local submitted
    local i = input.new({
      on_submit = function(text)
        submitted = text
      end,
    })
    local buf = i:ensure_buffer()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello", "world", "" })

    local ret = i:submit()
    assert.equal("hello\nworld", ret)
    assert.equal("hello\nworld", submitted)
    assert.same({ "" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("ignores blank submissions", function()
    local called = false
    local i = input.new({
      on_submit = function()
        called = true
      end,
    })
    local buf = i:ensure_buffer()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "   ", "" })

    assert.is_nil(i:submit())
    assert.is_false(called)
  end)

  it("preserves interior blank lines", function()
    local submitted
    local i = input.new({
      on_submit = function(text)
        submitted = text
      end,
    })
    local buf = i:ensure_buffer()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "", "b" })

    i:submit()
    assert.equal("a\n\nb", submitted)
  end)
end)
