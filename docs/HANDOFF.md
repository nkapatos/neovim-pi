# Handoff

For the next session/agent continuing this work.

## 1. Where things stand

- **Research complete** — `docs/RESEARCH.md` (reference/inspiration only).
- **Plan** — `docs/PLAN.md` (merged to `main`).
- **Iteration 0 merged** — package skeleton: load guard (>= 0.12.5), guarded
  `ui2`, `:checkhealth neovim-pi`, `doc/`, and a `justfile`.
- **Iteration 1 implemented** — `pi.adapter` (spawns `pi --mode rpc`, strict
  JSONL framing, id correlation), `pi.protocol` (unified vocabulary), a minimal
  streaming chat buffer, and `:Pi` / `:PiSend` / `:PiAbort` / `:PiStop` /
  `:PiStatus`. Unit specs, a real-process integration spec, and `just verify`.
- **Next: Iteration 2** — usable fresh-session TUI (real input buffer, model
  picker, statusline).

## 1a. Working notes

- `just` (mise), `stylua`, `luacheck`, and Neovim 0.12.5 are needed for local
  checks. `just setup-test` fetches `plenary.nvim` into gitignored `.deps/`.
- The adapter uses `vim.system` (not `jobstart`) because Pi requires strict
  byte-level JSONL framing; `vim.system` stdout runs in a fast-event context,
  so parsing is deferred with `vim.schedule`.

## 2. Git workflow (hard rule)

- **Never push to `main`** unless the user explicitly asks.
- Every change: create a branch, push the branch, open a PR for review.
- This session created branch `plan/out-of-box-ui2-pack` and opened a PR for the
  planning docs. Implementation branches should be named like
  `iter/0-pack-skeleton`, `iter/1-adapter`, etc.

## 3. Environment (ephemeral — redo in a fresh container)

The container has **no mapped volume to host**; nothing here persists. Redo:

```bash
# neovim (mise preinstalled; apt has no neovim candidate here)
mise use -g neovim@0.12.5

# dev-only test dependency
git clone --depth 1 https://github.com/nvim-lua/plenary.nvim .deps/plenary.nvim
```

`pi` is already on PATH in these containers (mise-installed). The container
clock is set to 2026; do not treat dates as authoritative.

## 4. GitHub repo

- Remote: `https://github.com/nkapatos/neovim-pi` (public).
- `gh` is installed and authenticated as `nkapatos` **in this container only**;
  auth is ephemeral. A fresh container needs the operator to re-authenticate.
  **Never** initiate a browser/device-code OAuth flow yourself.
- Push flow once authenticated:

```bash
gh auth setup-git
git config user.name  "nkapatos"
git config user.email "1628148+nkapatos@users.noreply.github.com"
git checkout -b <branch>
git add -A && git commit -m "..."
git push -u origin <branch>
gh pr create --base main --head <branch> --title "..." --body "..."
```

## 5. Constraints

- Keep notes under `/home/agent/docs`; do **not** create `AGENTS.md`/TODO files
  in the repo.
- Never write credentials/secrets into the repo.
- `/home/agent` (incl. `~/.pi/agent`) is ephemeral; do not copy it into the repo.
- Precedent ledger MCP: `http://192.168.64.19:8080/mcp`. In this container the
  pi extension's default URL was hardcoded to that (because `PRECEDENT_MCP_URL`
  was unset in the pi process env). Re-check in a fresh container.
- Standing precedent (apply during implementation): **use a `justfile` for task
  management** (build/test/vet/format/run/verify).

## 6. Next actions (ordered)

1. Start **Iteration 2** per `docs/PLAN.md` on a new branch (real input buffer,
   model picker, statusline), open a PR.
2. Then Iteration 3 (CLI-parity launch) and beyond.
