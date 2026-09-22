# neovim-pi

Neovim as the TUI for the [Pi](https://github.com/earendil-works/pi) coding-agent
harness.

**Status: early implementation — Iteration 3 (CLI-parity launch).**

## The one-line architecture

Pi owns all agent state (sessions, models, tools, compaction, approvals). nvim
only paints what Pi reports and forwards user input. nvim never reads Pi's
session storage and never re-derives agent state.

## Hard constraints

- **Built-in nvim first.** Exhaust out-of-the-box features (`vim.ui.*`,
  `jobstart`, floating windows, `ui2`, native `pack/`) before any third-party
  plugin. Third-party only if absolutely required and phase-justified.
- **Minimum nvim version: 0.12.5.**
- **Prefer the experimental `ui2`** (native messages/cmdline redesign) wherever
  possible.
- **Installable via Neovim's native `pack/` manager** (`pack/*/start/...` or
  `:packadd`).
- **Workflow:** no pushes to `main`; all work on a branch, push the branch, open
  a PR for review.

## Install

Requires Neovim >= 0.12.5 and `pi` on `$PATH`.

Native `pack/` (auto-loaded from `pack/*/start/`):

```sh
git clone https://github.com/nkapatos/neovim-pi \
  ~/.local/share/nvim/site/pack/core/start/neovim-pi
```

Or from `pack/*/opt/` with `:packadd neovim-pi`.

With the experimental `vim.pack` manager (Neovim 0.12), add to `init.lua` and
restart:

```lua
vim.pack.add({ 'https://github.com/nkapatos/neovim-pi' })
```

Run `:checkhealth neovim-pi` to verify the environment, and `:Pi` to confirm
the plugin loaded.

## Usage

`:Pi` opens the chat + input layout and starts `pi --mode rpc` in the resolved
project root if it is not already running. Compose a prompt in the input buffer
and send with `<C-s>` (insert) or `<CR>` (normal mode); `<CR>` in insert inserts
a newline. `:PiSend {text}` sends directly, `:PiAbort` (or `<Esc>` in the chat
buffer) aborts, `:PiModel` switches models, and `:PiStop` shuts Pi down. The
assistant transcript renders text, thinking, and tool calls distinctly, and the
statusline shows the model, thinking level, and streaming state. Pi owns all
session state; Neovim only renders what it reports.

`:PiStart` opens an interactive launch builder (session, trust, model, tools,
name) and shows the exact command before starting. `:PiCmd` prints the resolved
`pi …` command, cwd, and trust; `:PiTrust` reports the effective project-trust
decision. The spawn cwd is found LSP-style from markers (`.git`, `.pi`,
`package.json`, …), configurable via `setup({ launch = {...}, root_markers = {...} })`.

## Development

Tasks use [`just`](https://github.com/casey/just): `just --list`, `just verify`
(format + lint + headless smoke tests + plenary tests + `pack/` install test).
Tests need `stylua`, `luacheck`, and Neovim on `$PATH`; `just setup-test`
fetches the dev-only `plenary.nvim` dependency into `.deps/`.

## Roadmap

Iteration 0 (package skeleton) and Iteration 1 (transport + adapter) are done.
Next: a usable fresh-session TUI (input buffer, model picker, statusline), then
CLI-parity launch, resume + extension UI, and rendering fidelity. Pi owns all
agent state throughout; nvim only renders what Pi reports.
