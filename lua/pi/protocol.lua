--- Unified vocabulary + Pi RPC translation (anti-corruption layer).
---
--- This is one of only two modules that may know Pi's wire format (the other
--- is `pi.adapter`). The UI speaks the names below and never sees raw Pi RPC.
local M = {}

--- Unified events emitted by the adapter toward the UI.
M.EVENT = {
  READY = "ready",
  TEXT_DELTA = "text_delta",
  THINKING_DELTA = "thinking_delta",
  TOOL_START = "tool_start",
  TOOL_UPDATE = "tool_update",
  TOOL_END = "tool_end",
  MESSAGE_END = "message_end",
  TURN_END = "turn_end",
  SETTLED = "settled",
  UI_REQUEST = "ui_request",
  STATUS = "status",
  EXIT = "exit",
}

--- Unified operations. The UI calls these; `M.command` maps them to wire RPC.
M.OP = {
  PROMPT = "prompt",
  ABORT = "abort",
  NEW_SESSION = "new_session",
  GET_STATE = "get_state",
  GET_MESSAGES = "get_messages",
  GET_AVAILABLE_MODELS = "get_available_models",
  SET_MODEL = "set_model",
  SWITCH_SESSION = "switch_session",
  FORK = "fork",
  CLONE = "clone",
  RESPOND_UI = "ui_response",
  STOP = "stop",
}

--- Build the Pi wire command for a unified operation.
---
--- @param op string One of `M.OP`.
--- @param args table|nil
--- @return table|nil command
--- @return string|nil error
function M.command(op, args)
  args = args or {}
  if op == M.OP.PROMPT then
    local cmd = { type = "prompt", message = args.message }
    if args.streaming_behavior then
      cmd.streamingBehavior = args.streaming_behavior
    end
    return cmd
  elseif op == M.OP.ABORT then
    return { type = "abort" }
  elseif op == M.OP.NEW_SESSION then
    return { type = "new_session" }
  elseif op == M.OP.GET_STATE then
    return { type = "get_state" }
  elseif op == M.OP.GET_MESSAGES then
    return { type = "get_messages" }
  elseif op == M.OP.GET_AVAILABLE_MODELS then
    return { type = "get_available_models" }
  elseif op == M.OP.SET_MODEL then
    return { type = "set_model", provider = args.provider, modelId = args.model_id }
  elseif op == M.OP.SWITCH_SESSION then
    return { type = "switch_session", sessionPath = args.session_path }
  elseif op == M.OP.FORK then
    return { type = "fork", entryId = args.entry_id }
  elseif op == M.OP.CLONE then
    return { type = "clone" }
  elseif op == M.OP.RESPOND_UI then
    local cmd = { type = "extension_ui_response", id = args.id }
    if args.cancelled then
      cmd.cancelled = true
    elseif args.confirmed ~= nil then
      cmd.confirmed = args.confirmed
    elseif args.value ~= nil then
      cmd.value = args.value
    end
    return cmd
  end
  return nil, ("unknown operation: %s"):format(tostring(op))
end

--- Translate a Pi event into a unified event, or nil if it is not surfaced.
---
--- @param wire table
--- @return table|nil
function M.translate_event(wire)
  local kind = wire.type

  if kind == "message_update" then
    local ev = wire.assistantMessageEvent or {}
    if ev.type == "text_delta" then
      return { type = M.EVENT.TEXT_DELTA, text = ev.delta or "", index = ev.contentIndex }
    elseif ev.type == "thinking_delta" then
      return { type = M.EVENT.THINKING_DELTA, text = ev.delta or "", index = ev.contentIndex }
    elseif ev.type == "toolcall_start" then
      return { type = M.EVENT.TOOL_START, id = ev.id, name = ev.toolName }
    elseif ev.type == "toolcall_delta" then
      return { type = M.EVENT.TOOL_UPDATE, id = ev.id, delta = ev.delta }
    end
    return nil
  elseif kind == "message_end" then
    return { type = M.EVENT.MESSAGE_END, message = wire.message }
  elseif kind == "tool_execution_start" then
    return {
      type = M.EVENT.TOOL_START,
      id = wire.toolCallId,
      name = wire.toolName,
      args = wire.args,
    }
  elseif kind == "tool_execution_update" then
    return {
      type = M.EVENT.TOOL_UPDATE,
      id = wire.toolCallId,
      name = wire.toolName,
      partial = wire.partialResult,
    }
  elseif kind == "tool_execution_end" then
    return {
      type = M.EVENT.TOOL_END,
      id = wire.toolCallId,
      name = wire.toolName,
      result = wire.result,
      is_error = wire.isError,
    }
  elseif kind == "turn_end" then
    return { type = M.EVENT.TURN_END, message = wire.message, tool_results = wire.toolResults }
  elseif kind == "agent_settled" then
    return { type = M.EVENT.SETTLED }
  elseif kind == "extension_ui_request" then
    return { type = M.EVENT.UI_REQUEST, request = wire }
  elseif kind == "extension_error" then
    return {
      type = M.EVENT.STATUS,
      level = "error",
      message = ("extension error (%s): %s"):format(
        wire.extensionPath or "unknown",
        wire.error or "unknown"
      ),
    }
  end

  return nil
end

return M
