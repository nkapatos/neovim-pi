# Handoff

For the next session/agent continuing this work.

## 1. Where things stand

- **Research complete** — `docs/RESEARCH.md` (reference/inspiration only).
- **Plan drafted** — `docs/PLAN.md` (draft, under PR review).
- **Entry point for implementation** — `docs/START.md` (read this first; it
  says exactly what Iteration 0 is).
- **No implementation code exists** (deliberately). Any adapter scaffold from
  earlier exploratory discussion was removed and must not be reused without
  re-reviewing against `docs/PLAN.md`.

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

1. Review the open PR for `docs/` (planning updates).
2. On approval, start **Iteration 0** per `docs/START.md` on a new branch
   `iter/0-pack-skeleton`, open a PR.
3. Then Iteration 1 (adapter/transport) with plenary unit + integration tests,
   plus the `justfile` tasks.
