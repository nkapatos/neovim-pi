# Start here

This is the pointer file. A fresh session should read this file first, then
start implementing.

## Read, in order

1. [PLAN.md](PLAN.md) — architecture + the iterations (what to build, in order).
2. [HANDOFF.md](HANDOFF.md) — environment setup + git workflow + constraints.
3. [RESEARCH.md](RESEARCH.md) — reference/inspiration **only** (not a dependency
   list; built-in nvim features come first).

## First thing to implement — Iteration 0 (package skeleton)

**Goal:** make this repo installable via Neovim's native `pack/` package
manager, with nothing else assumed.

Deliverables (all under a feature branch, opened as a PR):

- Standard package layout at the repo root:
  - `plugin/neovim-pi.lua` — load guard + `:Pi` placeholder command.
  - `lua/pi/init.lua` — module entry; **version guard** (reject < 0.12.5).
  - `lua/pi/ui2.lua` — enable experimental `ui2` (guarded with `pcall`, since it
    is `vim._core.ui2`).
  - `lua/pi/health.lua` — `:checkhealth neovim-pi` reporting nvim version and
    whether `pi` is on PATH.
  - `doc/neovim-pi.txt` + `doc/tags` — help file.
  - `justfile` — task management (user preference: build/test/vet/format/run).
- Acceptance:
  1. `git clone` the repo into
     `~/.local/share/nvim/site/pack/<pack>/start/neovim-pi` and the plugin loads
     automatically; `:packadd neovim-pi` also works from `opt/`.
  2. `:checkhealth neovim-pi` runs and shows version + `pi` status.
  3. `:Pi` exists (placeholder) and proves the module loaded.
  4. Opening nvim < 0.12.5 produces a clear error, not a crash.

## Do not

- Push to `main`. Work on a branch, push the branch, open a PR.
- Add third-party plugin dependencies unless absolutely required and justified.
- Write credentials, `AGENTS.md`, or TODO files into the repo.
