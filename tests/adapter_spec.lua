local adapter_mod = require("pi.adapter")
local protocol = require("pi.protocol")

--- @return table adapter
--- @return table[] events
local function new_adapter()
  local events = {}
  local a = adapter_mod.new({
    on_event = function(event)
      events[#events + 1] = event
    end,
  })
  a._obj = { write = function() end } -- stub stdin so `request` works without a process
  return a, events
end

describe("pi.adapter correlation", function()
  it("correlates a successful response by id", function()
    local a = new_adapter()
    local got
    local id = a:request(protocol.command("get_state"), function(data, err)
      got = { data = data, err = err }
    end)
    assert.is_truthy(id)

    a:_consume(vim.json.encode({
      id = id,
      type = "response",
      command = "get_state",
      success = true,
      data = { n = 1 },
    }) .. "\n")
    assert.same({ n = 1 }, got.data)
    assert.is_nil(got.err)
  end)

  it("surfaces failure responses", function()
    local a = new_adapter()
    local got
    local id = a:request(protocol.command("get_state"), function(data, err)
      got = { data = data, err = err }
    end)
    a:_consume(vim.json.encode({
      id = id,
      type = "response",
      command = "get_state",
      success = false,
      error = "boom",
    }) .. "\n")
    assert.equal("boom", got.err)
  end)
end)

describe("pi.adapter dispatch", function()
  it("emits translated streaming events", function()
    local a, events = new_adapter()
    a:_consume(vim.json.encode({
      type = "message_update",
      assistantMessageEvent = { type = "text_delta", contentIndex = 0, delta = "Hello " },
    }) .. "\n")
    assert.equal(1, #events)
    assert.equal(protocol.EVENT.TEXT_DELTA, events[1].type)
    assert.equal("Hello ", events[1].text)
  end)

  it("frames across chunk boundaries", function()
    local a, events = new_adapter()
    a:_consume('{"type":"message_update","assistantMessageEvent":{"type":"text_delta"')
    assert.equal(0, #events)
    a:_consume(',"delta":"ok"}}\n')
    assert.equal(1, #events)
    assert.equal("ok", events[1].text)
  end)

  it("reports invalid JSON as a status event", function()
    local a, events = new_adapter()
    a:_consume("not json\n")
    assert.equal(protocol.EVENT.STATUS, events[1].type)
    assert.equal("error", events[1].level)
  end)

  it("delivers events through the scheduled stdout path", function()
    local a, events = new_adapter()
    a:_on_stdout(nil, '{"type":"agent_settled"}\n')
    vim.wait(1000, function()
      return #events > 0
    end)
    assert.equal(protocol.EVENT.SETTLED, events[1].type)
  end)
end)
