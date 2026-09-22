local extension = require("pi.ui.extension")

--- @return table
local function new_ctx()
  local c = {
    responses = {},
    notified = {},
    status = {},
    widgets = {},
  }
  c.respond = function(r)
    c.responses[#c.responses + 1] = r
  end
  c.notify = function(m, l)
    c.notified[#c.notified + 1] = { m, l }
  end
  c.set_status = function(k, t)
    c.status[k] = t
  end
  c.set_widget = function(k, l)
    c.widgets[k] = l
  end
  c.set_title = function(t)
    c.title = t
  end
  c.set_editor_text = function(t)
    c.editor_text = t
  end
  return c
end

describe("pi.ui.extension", function()
  local original_select = vim.ui.select
  local original_input = vim.ui.input

  after_each(function()
    vim.ui.select = original_select
    vim.ui.input = original_input
  end)

  it("answers select with the chosen value", function()
    local c = new_ctx()
    vim.ui.select = function(items, _, cb)
      cb(items[2])
    end
    extension.handle({ id = "1", method = "select", options = { "a", "b" } }, c)
    assert.equal("1", c.responses[1].id)
    assert.equal("b", c.responses[1].value)
  end)

  it("cancels a dismissed select", function()
    local c = new_ctx()
    vim.ui.select = function(_, _, cb)
      cb(nil)
    end
    extension.handle({ id = "2", method = "select", options = { "a" } }, c)
    assert.is_true(c.responses[1].cancelled)
  end)

  it("answers confirm with a boolean", function()
    local c = new_ctx()
    vim.ui.select = function(_, _, cb)
      cb("No")
    end
    extension.handle({ id = "3", method = "confirm", message = "?" }, c)
    assert.is_false(c.responses[1].confirmed)
  end)

  it("answers input with the typed value", function()
    local c = new_ctx()
    vim.ui.input = function(_, cb)
      cb("hello")
    end
    extension.handle({ id = "4", method = "input", title = "x" }, c)
    assert.equal("hello", c.responses[1].value)
  end)

  it("handles fire-and-forget methods", function()
    local c = new_ctx()
    extension.handle({ id = "5", method = "notify", message = "hi", notifyType = "warning" }, c)
    assert.equal("hi", c.notified[1][1])
    assert.equal(vim.log.levels.WARN, c.notified[1][2])

    extension.handle({ id = "6", method = "setStatus", statusKey = "k", statusText = "busy" }, c)
    assert.equal("busy", c.status["k"])

    extension.handle(
      { id = "7", method = "setWidget", widgetKey = "w", widgetLines = { "a", "b" } },
      c
    )
    assert.same({ "a", "b" }, c.widgets["w"])

    extension.handle({ id = "8", method = "setTitle", title = "T" }, c)
    assert.equal("T", c.title)

    extension.handle({ id = "9", method = "set_editor_text", text = "prefill" }, c)
    assert.equal("prefill", c.editor_text)
  end)
end)
