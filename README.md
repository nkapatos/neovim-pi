# neovim-pi

Neovim as the TUI for the [Pi](https://github.com/earendil-works/pi) coding-agent
harness.

**Status: early implementation — Iteration 0 (package skeleton).** See
[docs/PLAN.md](docs/PLAN.md) for the roadmap; implementation starts from
[docs/START.md](docs/START.md).

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

## Development

Tasks use [`just`](https://github.com/casey/just): `just --list`, `just verify`
(format + lint + headless smoke tests + plenary tests + `pack/` install test).
Tests need `stylua`, `luacheck`, and Neovim on `$PATH`; `just setup-test`
fetches the dev-only `plenary.nvim` dependency into `.deps/`.

## Documents

| Doc | Purpose |
| --- | --- |
| [docs/START.md](docs/START.md) | Entry point — start implementing here |
| [docs/PLAN.md](docs/PLAN.md) | Architecture + phased implementation plan |
| [docs/RESEARCH.md](docs/RESEARCH.md) | Ecosystem reference/inspiration (not deps) |
| [docs/HANDOFF.md](docs/HANDOFF.md) | Environment + git workflow for a fresh session |
