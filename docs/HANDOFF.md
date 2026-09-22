# Handoff

For the next session/agent continuing this work.

## 1. Where things stand

- **Research complete** — `docs/RESEARCH.md`.
- **Plan drafted, not approved** — `docs/PLAN.md`. Treat as a proposal; the user
  has not signed off on starting implementation.
- **No implementation code exists in this repo** (deliberately removed). Any Lua
  adapter scaffold from earlier in this session was exploratory and should not
  be reused without re-reviewing against `docs/PLAN.md`.

## 2. Environment (this container, ephemeral)

Nothing here persists to the host — the container has **no mapped volume**.
A fresh container must redo setup:

```bash
# neovim (mise is preinstalled; apt has no neovim candidate here)
mise use -g neovim@0.12.5

# test dependency
git clone --depth 1 https://github.com/nvim-lua/plenary.nvim .deps/plenary.nvim
```

`pi` itself is already on PATH in these containers (mise-installed).
Note: the container clock is set to 2026; do not treat dates as authoritative.

## 3. GitHub repo

- Remote: `https://github.com/nkapatos/neovim-pi` (public, currently docs-only).
- `gh` is installed and authenticated as `nkapatos` in this container, but that
  auth is **ephemeral** — a fresh container needs the operator to re-authenticate.
  **Never** initiate a browser/device-code OAuth flow yourself.
- Push flow once authenticated:

```bash
gh auth setup-git                                   # make git use gh's token
git config user.name  "nkapatos"
git config user.email "1628148+nkapatos@users.noreply.github.com"
git remote add origin https://github.com/nkapatos/neovim-pi.git
git add -A && git commit -m "docs: research and implementation plan"
git push -u origin main
```

## 4. Constraints to respect

- Keep notes/context under `/home/agent/docs`; do **not** create `AGENTS.md` or
  TODO files in the repo. Repo gets source + docs only.
- Never write credentials/secrets into the repo.
- `/home/agent` (including `~/.pi/agent`) is ephemeral; do not copy it into the
  repo or rely on it surviving.
- Precedent ledger is live (MCP at `http://192.168.64.19:8080/mcp`; the pi
  extension's default was hardcoded to that in this container because
  `PRECEDENT_MCP_URL` was not set in the pi process env).

## 5. Standing precedent (apply during implementation)

- **Use a `justfile` for task management** (user preference, preferred): build/
  test/vet/format/run/verify should live in a repo `justfile`, and CI/docs
  invoke `just` directly. Add it when implementation starts (not yet).

## 6. Next actions (ordered)

1. User approves/reviews `docs/PLAN.md` (esp. the dependency choice and the
   session-listing gap in §7).
2. On approval, start **Phase 0**: adapter + transport + minimal buffer
   rendering, with plenary unit tests for framing/translation and an
   integration test against `pi --mode rpc --no-session`.
3. Add the `justfile` (task management) alongside the first code.
4. Phase 1: real input buffer + model picker + statusline.
