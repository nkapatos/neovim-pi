local protocol = require("pi.protocol")

describe("pi.protocol", function()
  it("builds a prompt command", function()
    assert.same({ type = "prompt", message = "hi" }, protocol.command("prompt", { message = "hi" }))
  end)

  it("includes streamingBehavior when asked", function()
    local cmd = protocol.command("prompt", { message = "hi", streaming_behavior = "steer" })
    assert.equal("steer", cmd.streamingBehavior)
  end)

  it("builds abort and get_state", function()
    assert.same({ type = "abort" }, protocol.command("abort"))
    assert.same({ type = "get_state" }, protocol.command("get_state"))
  end)

  it("builds model and session commands", function()
    assert.same({ type = "get_available_models" }, protocol.command("get_available_models"))
    assert.same({
      type = "set_model",
      provider = "anthropic",
      modelId = "claude-sonnet-4",
    }, protocol.command("set_model", { provider = "anthropic", model_id = "claude-sonnet-4" }))
    assert.same({
      type = "switch_session",
      sessionPath = "/tmp/s.jsonl",
    }, protocol.command("switch_session", { session_path = "/tmp/s.jsonl" }))
  end)

  it("returns an error for unknown operations", function()
    local cmd, err = protocol.command("nope", {})
    assert.is_nil(cmd)
    assert.matches("unknown operation", err)
  end)

  it("translates text and thinking deltas", function()
    local text = protocol.translate_event({
      type = "message_update",
      assistantMessageEvent = { type = "text_delta", contentIndex = 0, delta = "Hi" },
    })
    assert.equal(protocol.EVENT.TEXT_DELTA, text.type)
    assert.equal("Hi", text.text)

    local thinking = protocol.translate_event({
      type = "message_update",
      assistantMessageEvent = { type = "thinking_delta", contentIndex = 0, delta = "..." },
    })
    assert.equal(protocol.EVENT.THINKING_DELTA, thinking.type)
  end)

  it("translates tool execution lifecycle", function()
    local start = protocol.translate_event({
      type = "tool_execution_start",
      toolCallId = "c1",
      toolName = "bash",
      args = { command = "ls" },
    })
    assert.equal(protocol.EVENT.TOOL_START, start.type)
    assert.equal("bash", start.name)

    local done = protocol.translate_event({
      type = "tool_execution_end",
      toolCallId = "c1",
      toolName = "bash",
      isError = true,
    })
    assert.equal(protocol.EVENT.TOOL_END, done.type)
    assert.is_true(done.is_error)
  end)

  it("maps agent_settled and ignores unknown events", function()
    assert.equal(protocol.EVENT.SETTLED, protocol.translate_event({ type = "agent_settled" }).type)
    assert.is_nil(protocol.translate_event({ type = "agent_start" }))
  end)
end)
