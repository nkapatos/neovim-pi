# neovim-pi

Neovim as the TUI for the [Pi](https://github.com/earendil-works/pi) coding-agent
harness.

**Status: research & planning.** Implementation starts from
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

## Documents

| Doc | Purpose |
| --- | --- |
| [docs/START.md](docs/START.md) | Entry point — start implementing here |
| [docs/PLAN.md](docs/PLAN.md) | Architecture + phased implementation plan |
| [docs/RESEARCH.md](docs/RESEARCH.md) | Ecosystem reference/inspiration (not deps) |
| [docs/HANDOFF.md](docs/HANDOFF.md) | Environment + git workflow for a fresh session |
