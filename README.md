# neovim-pi

Neovim as the TUI for the [Pi](https://github.com/earendil-works/pi) coding-agent
harness.

**Status: research & planning only.** No implementation has been started.

## The one-line architecture

Pi owns all agent state (sessions, models, tools, compaction, approvals). nvim
only paints what Pi reports and forwards user input. nvim never reads Pi's
session storage and never re-derives agent state.

## Documents

| Doc | Purpose |
| --- | --- |
| [docs/RESEARCH.md](docs/RESEARCH.md) | Neovim plugin ecosystem survey and reuse guidance |
| [docs/PLAN.md](docs/PLAN.md) | Phased implementation plan |
| [docs/HANDOFF.md](docs/HANDOFF.md) | Handoff notes for starting a fresh session |
