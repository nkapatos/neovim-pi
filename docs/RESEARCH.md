# Ecosystem Research

> **Role of this document:** reference and inspiration ONLY. This is **not** a
> dependency list. Policy is built-in nvim features first; a third-party plugin
> is added only if absolutely required and phase-justified (see `docs/PLAN.md`
> "Dependency policy"). The plugins below are studied for implementation
> details, not copied.

Goal: identify which existing Neovim plugins and libraries already solve pieces
of what we need (agent harness as backend, chat UI, streaming into a buffer,
sessions, buffers, diffs, pickers/inputs) so we reuse rather than reinvent.

Method: surveyed the actively maintained Neovim AI plugins and UI libraries via
GitHub (metadata + READMEs + key source files), September 2026.

---

## 1. The two plugin shapes

Every mature "AI in Neovim" plugin falls into one of two shapes:

| Shape | Examples | Characteristic | Relevance to us |
| --- | --- | --- | --- |
| **Monolith** — plugin is the harness | codecompanion.nvim, avante.nvim, CopilotChat.nvim | Owns adapters, strategies, prompts, chat storage, tools, session persistence in Lua/Neovim state | This is exactly the "plugin does too many things" pain we are avoiding |
| **Thin wrapper** — editor is a view over a backend | gp.nvim (HTTP), aider.nvim (terminal subprocess) | The backend does the work; the plugin is buffers + job/terminal plumbing | This is the shape we want, but over a **local agent harness** (Pi) |

No surveyed plugin does *exactly* what we want: a thin Neovim client over a
local agent harness's native headless protocol. The two closest analogs are
aider.nvim (thin client over a terminal CLI agent) and codecompanion's ACP
adapters (thin-ish client over CLI agents via a protocol). This gap is the
justification for building, but only the thin adapter layer is new.

---

## 2. Agent-coding plugins (patterns to study)

### codecompanion.nvim — `olimorris/codecompanion.nvim` (~6.9k ★, very active)

The most complete reference. Relevant even though it is the monolith we reject.

- **Chat buffer**: a dedicated scratch buffer with roles/separators/highlights.
  The design is credited to Steven Arcangeli. This is the reference chat UX.
- **ACP client** (`lua/codecompanion/acp/`): adapters for many CLI agents
  (opencode, claude_code, codex, goose, gemini_cli, cursor_cli, kimi_cli, …).
- **Lifecycle** (from `acp/init.lua`), which maps almost 1:1 onto what our
  adapter must do over Pi RPC:
  1. `start_agent_process()` — spawn the agent subprocess (guarded so a second
     caller doesn't spawn a duplicate and orphan the first);
  2. `_initialize()` — send `initialize`, negotiate `protocolVersion`;
  3. `_authenticate()` — optional auth handshake;
  4. `session/new` — create a session; **guarded against concurrent callers**
     (session creation is slow, and a race would replace the id mid-prompt);
  5. `session/load` — resume; checks the agent's capability first;
  6. `prompt` — stream updates; `session/update`, `permission_request`,
     and error forwarding are correlated to the active prompt by request id.
- **UI deps**: nui.nvim (inputs/popups), dressing.nvim (`vim.ui`).

**Takeaway:** copy the *lifecycle/state-machine pattern* and the chat-buffer
concept; do **not** copy the monolith (adapters + strategies + chat storage +
prompts all in one plugin).

### avante.nvim — `avante-corp/avante.nvim` (~18k ★, very active)

Cursor-like experience; the strongest diff/apply UX in the space.

- Sidebar + **side-by-side diff** with one-click apply — the reference for our
  diff/review UX.
- **ACP support** (codex, gemini, …) and a provider-backend abstraction
  (openai/anthropic/mistral/deepseek/ollama/copilot).
- Clean **seams** worth adopting:
  - `input` provider: `"native" | "snacks"` — pluggable input UI;
  - `file_selector` provider: telescope | mini.pick | fzf-lua.

**Takeaway:** reference for diff/apply and for the *pluggable input/selector
seam* (which is also where our anti-corruption layer lives, one level up).

### gp.nvim — `Robitx/gp.nvim` (~1.3k ★)

Minimal-dependency philosophy; closest in spirit to "nvim stays dumb."

- Chat = **plain markdown buffers** with autosave + a **chat finder**
  (search / preview / delete / open sessions).
- **Streaming** responses over `curl` into buffers.
- **Multiple output targets**: rewrite / prepend / append / new buffer / popup.
- Minimal deps: `nvim` + `curl` + `grep`.

**Takeaway:** the "buffers are the only UI, backend does the work" philosophy
and the chat-finder/session-picker pattern. But gp wraps HTTP providers and
stores chat history itself — we explicitly do **not** (Pi owns sessions).

### CopilotChat.nvim — `CopilotC-Nvim/CopilotChat.nvim` (~3.7k ★)

- **Context references**: `#buffer:active`, `#file:path`, `#<function>` — a good
  syntax to adopt for "eventually yes" buffer/selection context.
- **Sticky prompts** `>`, **model switch** `$`, `:CopilotChatModels`.
- Pickers via `vim.ui.select` (recommends snacks.picker).
- Chat buffer highlight groups and autocmd hooks.

**Takeaway:** adopt the `#context` reference syntax and model-switch command
shape; adopt custom highlight groups for the chat buffer.

### aider.nvim — `joshuavial/aider.nvim` (archived, ~560 ★)

The "harness as terminal subprocess" pattern.

- Opens a terminal running `aider`; **reattaches to the existing job** instead
  of spawning a duplicate.
- Auto-adds open buffers + git-modified files to the chat.

**Takeaway:** two things — (a) the *reattach-not-respawn* lifecycle rule we
already decided, and (b) the zero-integration fallback: run the `pi` TUI in a
toggleterm terminal while the plugin is still being built.

### Lower priority (skimmed, minimal reuse)

- **sg.nvim** (`sourcegraph/sg.nvim`, ~780 ★, experimental) — Cody sessions/chat.
- **gen.nvim** (`David-Kunz/gen.nvim`, ~1.5k ★) — prompt templates → selection/output.
- **neoai.nvim** (`Bryley/neoai.nvim`, ~570 ★) — older, minimal.

---

## 3. UI / utility libraries (reuse directly)

| Library | Stars | Use for | Notes |
| --- | --- | --- | --- |
| `folke/snacks.nvim` | ~8k | picker, input, notify, terminal | Modern one-dep choice; recommended by CopilotChat & avante as input provider |
| `nvim-telescope/telescope.nvim` | ~20k | pickers (session list, model list) | Use if the user already has it; otherwise snacks.picker |
| `MunifTanjim/nui.nvim` | ~2.1k | floating inputs/popups | Used by codecompanion; fallback if not using snacks |
| `stevearc/dressing.nvim` | ~2k | `vim.ui.select/input` polish | **Archived** — prefer snacks for new projects |
| `MeanderingProgrammer/render-markdown.nvim` | ~5k | markdown rendering in chat buffer | Only if we render markdown (Phase 4) |
| `akinsho/toggleterm.nvim` | ~5.6k | `pi` TUI fallback in a terminal | Zero-integration path + debugging |
| `folke/noice.nvim` | ~5.8k | nicer cmdline/messages for streaming status | Optional polish |
| `nvim-lua/plenary.nvim` | — | test harness | Standard for plugin tests |

**Dependency policy (proposed):** keep runtime deps minimal and composable —
one picker/input/notify source (snacks **or** telescope+dressing), plus
toggleterm for the fallback. Everything else is optional and phase-gated.

---

## 4. Agent Client Protocol (ACP) — future fallback, not primary

`agentclientprotocol/agent-client-protocol` (~4.3k ★, stable protocol **v1**).

- Standardizes editor ↔ coding agent via JSON-RPC: `initialize` (negotiates
  `protocolVersion`), `session/new`, `session/load`, `session/update`, `prompt`,
  `permission_request`.
- SDKs: Kotlin, Java, Python, Rust, TypeScript.
- codecompanion's `lua/codecompanion/acp/` is the reference *client*
  implementation; many CLI agents already ship ACP servers.

**Decision:** Pi does **not** implement ACP today — it has its own native,
richer JSONL RPC (`pi --mode rpc`). We use Pi RPC as primary. The anti-corruption
layer (adapter seam) is what makes an ACP adapter feasible later, either against
another harness or against a thin Pi→ACP bridge. Do not build ACP support until
a second harness or a Pi ACP server is actually in play.

---

## 5. Reuse vs. build — the guidance

**Reuse (add as deps, don't write):**
- picker/input/notify → snacks.nvim (or telescope + dressing)
- terminal fallback → toggleterm.nvim
- markdown rendering → render-markdown.nvim (Phase 4, optional)
- test harness → plenary.nvim

**Study, then build a thin version of:**
- chat buffer concept (codecompanion, credited to Steven Arcangeli)
- harness lifecycle/state machine (codecompanion `acp/init.lua`)
- diff/apply UX (avante)
- `#context` reference syntax (CopilotChat)
- streaming + chat-finder/session-picker (gp.nvim)
- reattach-not-respawn + buffer-context auto-add (aider.nvim)

**Build ourselves (the only genuinely new code):**
- the Pi RPC adapter (anti-corruption layer): spawn `pi --mode rpc`, strict
  JSONL framing, translate wire ↔ unified vocabulary, request/response
  correlation, extension-UI sub-protocol.
- the "nvim never owns agent state" rule — this is the deliberate divergence
  from gp/CopilotChat/codecompanion, which all persist their own chat history.

---

## 6. References

- codecompanion.nvim — https://github.com/olimorris/codecompanion.nvim
- avante.nvim — https://github.com/avante-corp/avante.nvim
- gp.nvim — https://github.com/Robitx/gp.nvim
- CopilotChat.nvim — https://github.com/CopilotC-Nvim/CopilotChat.nvim
- aider.nvim — https://github.com/joshuavial/aider.nvim
- snacks.nvim — https://github.com/folke/snacks.nvim
- nui.nvim — https://github.com/MunifTanjim/nui.nvim
- render-markdown.nvim — https://github.com/MeanderingProgrammer/render-markdown.nvim
- toggleterm.nvim — https://github.com/akinsho/toggleterm.nvim
- Agent Client Protocol — https://github.com/agentclientprotocol/agent-client-protocol
- Pi RPC mode — `docs/rpc.md` in the pi-coding-agent package (headless JSONL protocol)
