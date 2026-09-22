# Implementation Plan

Status: **draft for approval — no code written yet.**

## 1. Goal

Make Neovim the TUI for the Pi coding-agent harness. Pi owns all agent state;
nvim is a thin renderer + input surface + launcher.

## 2. Principles (locked decisions)

1. **One nvim instance = one Pi RPC process = one Pi session.** Multiple agents
   = multiple nvim instances. No multiplexing. (Pi distinguishes *agents* from
   *branches* — forks within one session are renderable later via `get_tree`.)
2. **nvim paints, Pi owns state.** nvim requests transcripts from Pi
   (`get_messages`/`get_entries`/`get_tree`); it never reads session files or
   re-derives state. Start fresh like the TUI; resume only by explicit action.
3. **CWD = project root**, resolved the way LSP tooling does (rooter/git-root),
   not nvim's global `getcwd()`.
4. **Fresh start every time; no arg persistence.** The start UI is an argv
   builder for `pi --mode rpc`, mirroring the CLI (`pi --no-session`, tool
   flags, trust flags, `--name`, `--provider/--model`, …). Resume/fork are
   *post-attach commands* (`switch_session`/`fork`), not launch flags.
5. **On Pi exit: show end-state, nothing more** (TUI parity). No reconnect magic.
6. **Pi extensions, not nvim, provide custom commands/UI.** The extension-UI
   sub-protocol (`select`/`confirm`/`input`/`editor`/`notify`/`setStatus`) is
   rendered generically by nvim.
7. **Anti-corruption layer:** the only code that knows Pi's wire format is the
   adapter; the UI speaks a stable unified vocabulary. This absorbs Pi RPC
   churn and enables future harnesses/ACP.

## 3. Architecture

```
┌─────────────────────────────────────────────┐
│ nvim UI (buffers, pickers, input, diff)      │  ← speaks unified vocabulary
├─────────────────────────────────────────────┤
│ adapter (anti-corruption layer)              │  ← only code that knows Pi RPC
├─────────────────────────────────────────────┤
│ pi --mode rpc (child process, JSONL stdio)   │  ← owns all agent state
└─────────────────────────────────────────────┘
```

Unified vocabulary (nvim-facing, Pi-agnostic):

- **Ops:** `start`, `prompt`, `steer`, `abort`, `set_model`, `get_state`,
  `get_available_models`, `switch_session`, `new_session`, `ui_response`, `stop`.
- **Events:** `ready`, `text_delta`, `thinking_delta`, `tool_start`,
  `tool_update`, `tool_end`, `message_end`, `turn_end`, `settled`, `state`,
  `ui_request`, `status`, `exit`.

(Full Pi RPC surface is summarized in §8; the adapter maps it to the above.)

## 4. Phases

### Phase 0 — Transport + adapter (foundation)
- Adapter spawns `pi --mode rpc` (minimal hardcoded argv), strict JSONL framing
  (split on LF only, strip CR — do **not** use nvim line-buffered job output,
  because Pi forbids treating U+2028/U+2029 as separators).
- Translate wire → unified events; `send`/`request` with id correlation.
- Coalesce deltas and flush to a scratch buffer on `vim.schedule`.
- **Milestone:** attach to Pi, stream raw text into a buffer, Esc→abort,
  clean shutdown.

### Phase 1 — Usable fresh-session TUI
- Real input buffer (a nvim buffer as the editor), not `vim.fn.input`.
- Render text/thinking/tool-call blocks; statusline from `get_state`
  (model, streaming state, session name).
- Model picker: `get_available_models` → picker (snacks/telescope) → `set_model`.
- **Milestone:** complete a coding task in nvim against a fresh Pi session.

### Phase 2 — CLI-parity launch
- LSP-style rooter for spawn cwd.
- Start dialog = argv builder over Pi's flags (session/tool/trust/model).
- Surface effective project-trust state (RPC mode applies `defaultProjectTrust`
  silently; `-a`/`-na` override per run).
- **Milestone:** starting via nvim ≡ typing the equivalent `pi …` command.

### Phase 3 — Resume + extension UI
- `switch_session`/`fork` by explicit path (no session *picker* yet — see §7).
- Render extension-UI sub-protocol: `select`/`confirm` → picker/`vim.ui.input`,
  `editor` → floating buffer, `notify`/`setStatus`/`setWidget`/`setTitle` →
  notify/statusline/winbar.
- **Milestone:** a Pi extension with an interactive prompt works end-to-end.

### Phase 4 — Fidelity + Pi-side capability
- Thinking collapse, markdown/code highlighting (render-markdown), diff gutter
  on tool writes, session tree (`get_tree`), stats footer, steering queue.
- Session **listing** (see §7): decide Pi plugin vs. small fork; expose as an
  adapter `list_sessions` op that degrades gracefully until Pi supports it.
- Adapter hardening: pin Pi RPC surface, tests against `pi --mode rpc`.

## 5. Dependency choices (from research)

- Picker/input/notify: **snacks.nvim** (or telescope + dressing if user prefers).
- Terminal fallback (run `pi` TUI in a term): **toggleterm.nvim**.
- Markdown rendering (Phase 4): **render-markdown.nvim** (optional).
- Tests: **plenary.nvim**.

## 6. Testing strategy

- **Unit:** adapter framing (`_on_stdout` with crafted chunks incl. CRLF and
  U+2028/U+2029), wire→unified translation, request/response correlation.
  No real process needed (feed bytes directly, assert emitted events).
- **Integration:** spawn `pi --mode rpc --no-session`; exercise non-LLM commands
  (`get_state`, `get_available_models`, `new_session`, `abort`) and assert
  `response` handling. Skip gracefully if `pi` is absent.
- **Smoke:** headless nvim boots the plugin against `pi --mode rpc` for N
  seconds (guards against regressions in the startup path).
- Task management via `justfile` (user preference — see HANDOFF).

## 7. Known gaps / risks

1. **Pi RPC has no session-listing command.** The TUI's `/resume` and
   `SessionManager.list()` exist, but are not exposed over RPC. Session
   *picker* therefore needs a Pi extension or a small fork (a `list_sessions`
   RPC command). Deferred past Phase 3; `switch_session`-by-path unblocks
   resume earlier.
2. **Project trust diverges in RPC mode.** No interactive trust prompt; default
   `ask` silently ignores project resources. Mitigate by exposing `-a`/`-na`
   and showing effective trust state (Phase 2).
3. **No built-in permission popups in Pi** (deliberate — usage.md). Tool
   availability is config (`--tools`/`--exclude-tools`/…), not per-call prompts.
   So there is no approval modal to build; only extension dialogs (Phase 3).
4. **Streaming render performance** — coalesce deltas; don't call
   `nvim_buf_set_lines` per delta.
5. **Adapter drift** — pin/version the Pi RPC surface and keep a smoke test so
   Pi upgrades that change RPC fail loudly.

## 8. Pi RPC surface reference (summary)

`pi --mode rpc` = bidirectional JSONL over stdin/stdout. One JSON object per
line; LF is the only record delimiter (strip optional trailing CR).

Key **commands** (nvim → Pi): `prompt` (+`streamingBehavior`), `steer`,
`follow_up`, `abort`, `clear_queue`, `new_session`, `switch_session`, `fork`,
`clone`, `get_entries` (+`since` cursor), `get_tree`, `get_messages`,
`get_state`, `get_session_stats`, `get_commands`, `get_available_models`,
`set_model`, `cycle_model`, `set_thinking_level`, `set_auto_compaction`,
`set_auto_retry`, `bash`, `export_html`, `set_session_name`, and the
extension-UI responses (`extension_ui_response`).

Key **events** (Pi → nvim): `agent_start`/`agent_end`/`agent_settled`,
`turn_start`/`turn_end`, `message_start`/`message_update`/`message_end`
(`message_update` carries `text_delta`/`thinking_delta`/`toolcall_*`),
`tool_execution_start`/`update`/`end`, `queue_update`,
`compaction_start`/`end`, `auto_retry_*`, `extension_ui_request`,
`extension_error`, `bash_execution_update`.

Full reference: `docs/rpc.md` in the pi-coding-agent package (also `json.md` for
the fire-and-forget `pi --mode json` event stream, and `sdk.md` for the
in-process Node SDK — not needed for a Lua client).
