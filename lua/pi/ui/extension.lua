--- Rendering of Pi's extension-UI sub-protocol.
---
--- Dialog methods (`select`, `confirm`, `input`, `editor`) must be answered with
--- an `extension_ui_response`; fire-and-forget methods (`notify`, `setStatus`,
--- `setWidget`, `setTitle`, `set_editor_text`) are displayed and ignored. The
--- `ctx` callbacks are provided by the session.
local M = {}

local NOTIFY_LEVELS = {
  info = vim.log.levels.INFO,
  warning = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
}

--- @param request table
--- @param respond fun(response: table)
local function open_editor(request, respond)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(
    buf,
    0,
    -1,
    false,
    vim.split(request.prefill or "", "\n", { plain = true })
  )
  vim.bo[buf].filetype = "pi-editor"

  local width = math.max(20, math.min(80, vim.o.columns - 4))
  local height = math.max(3, math.min(20, vim.o.lines - 4))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = " pi: " .. (request.title or "editor") .. " ",
  })

  local function close()
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  local function submit()
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    respond({ id = request.id, value = text })
    close()
  end
  local function cancel()
    respond({ id = request.id, cancelled = true })
    close()
  end

  vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf, desc = "pi: submit" })
  vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, desc = "pi: cancel" })
  vim.cmd("startinsert")
end

--- Handle one `extension_ui_request`.
---
--- @param request table
--- @param ctx table
function M.handle(request, ctx)
  local method = request.method
  if method == "select" then
    vim.ui.select(request.options or {}, { prompt = request.title or "Select" }, function(choice)
      if choice == nil then
        ctx.respond({ id = request.id, cancelled = true })
      else
        ctx.respond({ id = request.id, value = choice })
      end
    end)
  elseif method == "confirm" then
    vim.ui.select(
      { "Yes", "No" },
      { prompt = request.message or request.title or "Confirm?" },
      function(choice)
        if choice == nil then
          ctx.respond({ id = request.id, cancelled = true })
        else
          ctx.respond({ id = request.id, confirmed = choice == "Yes" })
        end
      end
    )
  elseif method == "input" then
    vim.ui.input(
      { prompt = (request.title or "Input") .. ": ", default = request.placeholder or "" },
      function(value)
        if value == nil then
          ctx.respond({ id = request.id, cancelled = true })
        else
          ctx.respond({ id = request.id, value = value })
        end
      end
    )
  elseif method == "editor" then
    open_editor(request, function(response)
      ctx.respond(response)
    end)
  elseif method == "notify" then
    ctx.notify(request.message or "", NOTIFY_LEVELS[request.notifyType] or vim.log.levels.INFO)
  elseif method == "setStatus" then
    ctx.set_status(request.statusKey or "default", request.statusText)
  elseif method == "setWidget" then
    ctx.set_widget(request.widgetKey or "default", request.widgetLines)
  elseif method == "setTitle" then
    ctx.set_title(request.title or "")
  elseif method == "set_editor_text" then
    ctx.set_editor_text(request.text or "")
  end
end

return M
