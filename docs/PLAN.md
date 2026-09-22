# Implementation Plan

Status: **draft for review (PR). No implementation code yet.**

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
   builder for `pi --mode rpc`, mirroring the CLI. Resume/fork are
   *post-attach commands* (`switch_session`/`fork`), not launch flags.
5. **On Pi exit: show end-state, nothing more** (TUI parity). No reconnect magic.
6. **Pi extensions, not nvim, provide custom commands/UI.** The extension-UI
   sub-protocol is rendered generically by nvim.
7. **Anti-corruption layer:** the only code that knows Pi's wire format is the
   adapter; the UI speaks a stable unified vocabulary.
8. **Built-in nvim first** (see §4). Minimum nvim **0.12.5**. Prefer the
   experimental **`ui2`** for messages/cmdline (see §5).
9. **Workflow:** no pushes to `main`; every change on a branch + PR.

## 3. Architecture

```
┌─────────────────────────────────────────────┐
│ nvim UI (buffers, native pickers/input/diff) │  ← speaks unified vocabulary
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

(Full Pi RPC surface is summarized in §10; the adapter maps it to the above.)

## 3a. Transport rationale — stdio JSONL now, nvim RPC later (as a second channel)

nvim ↔ Pi uses Pi's native headless protocol: `pi --mode rpc`, JSONL over the
child process's stdin/stdout. Why this boundary and not Neovim's own IPC/RPC:

- It is Pi's intended embedding surface and carries the full event surface
  (streaming deltas, tool lifecycle, compaction/retry, extension-UI dialogs).
- No Pi-side change, bridge, or fork; stdio is universal and dependency-free.
- Neovim IPC/RPC (msgpack-RPC over a socket, or `jobstart({ rpc = true })`) is a
  poor fit here: Pi does not speak msgpack and exposes no documented
  socket-client mode, so using it would force a bridge or invert the
  architecture (Pi connecting out to a listening nvim), contradicting "Pi owns
  state; nvim is a thin renderer". It buys no capability for this link.

The `pi.adapter` / `pi.protocol` seam keeps the transport swappable: an ACP or
socket adapter can be added later without changing the unified vocabulary.

### Future: pushing rich context nvim → Pi

Later iterations need to send more than a prompt string — buffer contents or
selections ("chunks"), diagnostics, error messages, and other editor context.
Two layers, in order:

1. **Prompt expansion (default, no Pi change).** nvim resolves context
   references (`#buffer`, `#selection`, `#diagnostics`, `#file:path`; see
   `docs/RESEARCH.md`) into the `prompt` message before sending. This works with
   today's RPC surface.
2. **Structured context (deferred).** If Pi grows a structured
   context/attachment channel (or a Pi extension provides one), the adapter maps
   it through the same unified vocabulary. Do not fork Pi for this.

### Future: Pi using nvim remotely ("nvim as a service")

Mid/long term, Pi (or a Pi extension) may want native editor capabilities —
open a diff, set marks, apply edits to live buffers, query state — instead of
the generic extension-UI sub-protocol. That is where Neovim IPC/RPC *is* the
right tool: expose an outbound control channel (e.g. `:PiServe` / `nvim
--listen` / the `$NVIM` socket) that Pi can connect to and call `nvim_*` APIs
on. This is **additive** to the JSONL agent link, not a replacement: keep the
agent transport as-is and add the editor-control surface alongside it.

## 4. Dependency policy: built-ins first

Layer 0 — **required, built-in nvim 0.12.5 only:**

- `vim.system` for the Pi child process: raw byte stdout (strict JSONL
  framing), with parsing deferred to `vim.schedule` because its callbacks run
  in a fast-event context (§3a). `jobstart`/`chansend`/`jobstop` remain a
  fallback if `vim.system` proves insufficient.
- `vim.ui.select` / `vim.ui.input` / `vim.notify` (built-in indirection points;
  users may remap these themselves — we do not hard-depend on any picker)
- floating windows (`nvim_open_win`) + `buf`/`win` APIs (chat buffer, diffs)
- `ui2` (messages/cmdline/dialog/pager) and optionally `vim.ui_attach`
- `vim.json`, `vim.schedule`, `:checkhealth`, native `pack/`

Layer 1 — **third-party, only if absolutely required.** Each addition must be
phase-justified in a PR. `docs/RESEARCH.md` is the reference for *how* other
plugins solved a problem, not a shopping list. Candidates (to justify, never
assume): `plenary.nvim` (tests only, dev dependency), and only later possibly a
picker/input/markdown-rendering plugin if the built-ins prove genuinely
insufficient.

Rationale: this plugin is a TUI over a harness, not a general AI plugin. Its
unique work is the adapter; the UI surface should stay as close to nvim-native
as possible so it is predictable and easy to audit.

## 5. `ui2` (experimental messages/cmdline) — what it is and how we use it

Neovim 0.12.x ships an experimental redesign of the core messages + commandline
presentation layer, enabled with:

```lua
require('vim._core.ui2').enable()  -- experimental; guard with pcall
```

What it gives us (from `:help ui2`, `:help news`):

- Replaces the legacy message grid; **no "Press ENTER" interruptions**; no
  `W10` warning delays.
- Four special windows/buffers with `filetype` set to their id: `cmd`, `msg`,
  `pager`, `dialog` (configure via `FileType` autocmd).
- Cmdline highlighted as you type; **`cmdheight=0` works better** with ui2.
- Messages overflow into a "spill" indicator; `g<` opens the pager.

How we use it:

- Enable `ui2` at plugin load (guarded). It is our messages/cmdline/dialog
  layer — we do **not** depend on third-party message UIs.
- Route status/errors through `vim.notify` (lands in the ui2 messages area).
- Modal confirmations (`extension_ui_request` → `confirm`/`select`) use the
  native dialog surface / `vim.ui.select`, not a custom float, unless the UX
  genuinely requires it.
- Prompt input uses the cmdline (ui2-enhanced) or a dedicated input buffer;
  decide in Iteration 2 based on multi-line needs.

Related, also experimental: `vim.ui_attach(ns, opts, cb)` subscribes to UI
events in-process (popupmenu/messages) for custom screen elements. Not needed
for Iterations 0–3; revisit only if we implement custom rendering.

## 6. Iterations

### Iteration 0 — package skeleton (vim.pack installable)
See [START.md](START.md). Standard `plugin/` + `lua/` + `doc/` layout, version
guard (≥0.12.5), ui2 enable (guarded), `:checkhealth neovim-pi`, placeholder
`:Pi`, and a `justfile`. **No agent logic yet.**

### Iteration 1 — transport + adapter (foundation)
- Adapter spawns `pi --mode rpc` (minimal hardcoded argv), strict JSONL framing
  (split on LF only, strip CR — do **not** use nvim line-buffered job output,
  because Pi forbids treating U+2028/U+2029 as separators).
- Translate wire → unified events; `send`/`request` with id correlation.
- Coalesce deltas and flush to a scratch buffer on `vim.schedule`.
- **Milestone:** attach to Pi, stream raw text into a buffer, Esc→abort,
  clean shutdown.

### Iteration 2 — usable fresh-session TUI
- Real input buffer (a nvim buffer as the editor), not `vim.fn.input`.
- Render text/thinking/tool-call blocks; statusline from `get_state`.
- Model picker: `get_available_models` → `vim.ui.select` → `set_model`.
- **Milestone:** complete a coding task in nvim against a fresh Pi session.

### Iteration 3 — CLI-parity launch
- LSP-style rooter for spawn cwd.
- Start dialog = argv builder over Pi's flags (session/tool/trust/model).
- Surface effective project-trust state (RPC mode applies `defaultProjectTrust`
  silently; `-a`/`-na` override per run).
- **Milestone:** starting via nvim ≡ typing the equivalent `pi …` command.

### Iteration 4 — resume + extension UI
- `switch_session`/`fork` by explicit path (no session *picker* yet — see §9).
- Render extension-UI sub-protocol: `select`/`confirm` → `vim.ui.select`/input,
  `editor` → floating buffer, `notify`/`setStatus`/`setWidget`/`setTitle` →
  `vim.notify`/statusline/winbar.
- **Milestone:** a Pi extension with an interactive prompt works end-to-end.

### Iteration 5 — fidelity + Pi-side capability
- Thinking collapse, markdown/code highlighting, diff gutter on tool writes,
  session tree (`get_tree`), stats footer, steering queue.
- Session **listing** (see §9): decide Pi plugin vs. small fork; expose as an
  adapter `list_sessions` op that degrades gracefully until Pi supports it.
- Adapter hardening: pin Pi RPC surface, tests against `pi --mode rpc`.

## 7. Testing strategy

- **Unit:** adapter framing (`_on_stdout` with crafted chunks incl. CRLF and
  U+2028/U+2029), wire→unified translation, request/response correlation.
  No real process needed.
- **Integration:** spawn `pi --mode rpc --no-session`; exercise non-LLM commands
  (`get_state`, `get_available_models`, `new_session`, `abort`) and assert
  `response` handling. Skip gracefully if `pi` is absent.
- **Smoke:** headless nvim boots the plugin against `pi --mode rpc` for N
  seconds.
- Test dependency (`plenary.nvim`) is a **dev-only** dependency, not a runtime
  dependency; document it in `justfile` + `just setup-test`.
- Task management via `justfile` (user preference).

## 8. Package layout (target)

```
neovim-pi/
├── plugin/neovim-pi.lua        # load guard, :Pi etc.
├── lua/pi/
│   ├── init.lua                # setup, version guard, ui2 enable
│   ├── adapter.lua             # anti-corruption layer (Pi RPC)
│   ├── protocol.lua            # unified vocabulary
│   ├── ui/…                    # buffers, input, diff (later)
│   └── health.lua              # :checkhealth
├── doc/neovim-pi.txt + doc/tags
├── tests/                      # plenary specs (dev)
├── justfile
└── README.md, docs/
```

Install: `~/.local/share/nvim/site/pack/<pack>/start/neovim-pi` (auto) or
`.../opt/neovim-pi` + `:packadd neovim-pi`.

## 9. Known gaps / risks

1. **Pi RPC has no session-listing command.** The TUI's `/resume` and
   `SessionManager.list()` exist, but are not exposed over RPC. Session
   *picker* therefore needs a Pi extension or a small fork (a `list_sessions`
   RPC command). Deferred past Iteration 4; `switch_session`-by-path unblocks
   resume earlier.
2. **Project trust diverges in RPC mode.** No interactive trust prompt; default
   `ask` silently ignores project resources. Mitigate by exposing `-a`/`-na`
   and showing effective trust state (Iteration 3).
3. **No built-in permission popups in Pi** (deliberate). Tool availability is
   config (`--tools`/`--exclude-tools`/…), not per-call prompts. Only extension
   dialogs need rendering (Iteration 4).
4. **Streaming render performance** — coalesce deltas; don't call
   `nvim_buf_set_lines` per delta.
5. **Adapter drift** — pin/version the Pi RPC surface and keep a smoke test so
   Pi upgrades that change RPC fail loudly.
6. **`ui2` and `vim.ui_attach` are experimental** — always guard with `pcall`
   and feature-detect; degrade to legacy message/cmdline UI.

## 10. Pi RPC surface reference (summary)

`pi --mode rpc` = bidirectional JSONL over stdin/stdout. One JSON object per
line; LF is the only record delimiter (strip optional trailing CR).

Key **commands** (nvim → Pi): `prompt` (+`streamingBehavior`), `steer`,
`follow_up`, `abort`, `clear_queue`, `new_session`, `switch_session`, `fork`,
`clone`, `get_entries` (+`since` cursor), `get_tree`, `get_messages`,
`get_state`, `get_session_stats`, `get_commands`, `get_available_models`,
`set_model`, `cycle_model`, `set_thinking_level`, `set_auto_compaction`,
`set_auto_retry`, `bash`, `export_html`, `set_session_name`, and
`extension_ui_response`.

Key **events** (Pi → nvim): `agent_start`/`agent_end`/`agent_settled`,
`turn_start`/`turn_end`, `message_start`/`message_update`/`message_end`
(`message_update` carries `text_delta`/`thinking_delta`/`toolcall_*`),
`tool_execution_start`/`update`/`end`, `queue_update`, `compaction_start`/`end`,
`auto_retry_*`, `extension_ui_request`, `extension_error`,
`bash_execution_update`.

Full reference: `docs/rpc.md` in the pi-coding-agent package (also `json.md` for
the fire-and-forget `pi --mode json` stream, and `sdk.md` for the in-process
Node SDK — not needed for a Lua client).
