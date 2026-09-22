# neovim-pi task runner.
#
# `just --list` shows all tasks. `just verify` runs the full local gate.

set shell := ["bash", "-euo", "pipefail", "-c"]

repo := justfile_directory()
deps := repo + "/.deps"
plenary := deps + "/plenary.nvim"

# List available tasks.
default:
    @just --list

# Generate doc/tags so `:help neovim-pi` works.
build:
    nvim --headless --clean -c "helptags doc" -c "qa!"
    @echo "generated doc/tags"

# Format Lua sources in place with stylua.
format:
    stylua lua plugin tests

# Check formatting without writing.
format-check:
    stylua --check lua plugin tests

# Static analysis with luacheck.
vet:
    luacheck lua plugin tests

# Load the plugin in a clean headless Neovim and prove it registered.
check:
    nvim --headless --clean --cmd "set rtp^={{repo}}" \
      -c "lua assert(vim.g.loaded_neovim_pi == 1, 'plugin did not load')" \
      -c "lua assert(vim.fn.exists(':Pi') == 2, ':Pi is missing')" \
      -c "qa!"

# Prove an unsupported Neovim gets a clear error, not a crash (acceptance #4).
check-unsupported:
    nvim --headless --clean --cmd "set rtp^={{repo}}" \
      --cmd "lua vim.version = function() return { major = 0, minor = 11, patch = 0 } end" \
      -c "lua assert(vim.g.loaded_neovim_pi == 1, 'guard did not run')" \
      -c "lua assert(vim.fn.exists(':Pi') == 0, ':Pi should not exist on unsupported Neovim')" \
      -c "qa!"

# Install the dev-only test dependency (plenary.nvim).
setup-test:
    @test -d "{{plenary}}" || git clone --depth 1 https://github.com/nvim-lua/plenary.nvim "{{plenary}}"

# Run the plenary test suite.
test: setup-test
    nvim --headless --clean \
      --cmd "set rtp^={{repo}}" \
      --cmd "set rtp^={{plenary}}" \
      -c "runtime plugin/plenary.vim" \
      -c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua', sequential = true }"

# Verify a real `pack/*/start` install is picked up automatically (acceptance #1).
test-pack:
    tmp="$$(mktemp -d)"; \
    trap 'rm -rf "$$tmp"' EXIT; \
    mkdir -p "$$tmp/site/pack/neovim-pi-test/start"; \
    ln -s "{{repo}}" "$$tmp/site/pack/neovim-pi-test/start/neovim-pi"; \
    nvim --headless --clean --cmd "set packpath^=$$tmp/site" \
      -c "lua assert(vim.g.loaded_neovim_pi == 1, 'pack/start plugin did not load')" \
      -c "lua assert(vim.fn.exists(':Pi') == 2, ':Pi is missing')" \
      -c "qa!"

# Verify `:packadd` from a `pack/*/opt` install works (acceptance #1).
test-packadd:
    tmp="$$(mktemp -d)"; \
    trap 'rm -rf "$$tmp"' EXIT; \
    mkdir -p "$$tmp/site/pack/neovim-pi-test/opt"; \
    ln -s "{{repo}}" "$$tmp/site/pack/neovim-pi-test/opt/neovim-pi"; \
    nvim --headless --clean --cmd "set packpath^=$$tmp/site" \
      -c "packadd neovim-pi" \
      -c "lua assert(vim.g.loaded_neovim_pi == 1, ':packadd did not load plugin')" \
      -c "lua assert(vim.fn.exists(':Pi') == 2, ':Pi is missing')" \
      -c "qa!"

# Interactive run of Neovim with this plugin on the runtimepath.
run:
    nvim --cmd "set rtp^={{repo}}"

# Full local gate.
verify: build format-check vet check check-unsupported test test-pack test-packadd
    @echo "all checks passed"
