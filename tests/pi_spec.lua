local pi = require("pi")

describe("pi version guard", function()
  it("parses MAJOR.MINOR.PATCH", function()
    assert.same({ 0, 12, 5 }, pi.parse_version("0.12.5"))
    assert.same({ 1, 2, 3 }, pi.parse_version("1.2.3"))
  end)

  it("returns nil for unparseable versions", function()
    assert.is_nil(pi.parse_version("banana"))
    assert.is_nil(pi.parse_version("0.12"))
  end)

  it("compares versions", function()
    assert.is_true(pi.version_lt("0.11.9", "0.12.0"))
    assert.is_true(pi.version_lt("0.12.4", "0.12.5"))
    assert.is_false(pi.version_lt("0.12.5", "0.12.5"))
    assert.is_false(pi.version_lt("1.0.0", "0.12.5"))
  end)

  it("reports the running Neovim as supported", function()
    local supported, current = pi.is_supported()
    assert.is_true(supported)
    assert.equal("0.12.5", current)
  end)

  it("rejects an older Neovim", function()
    local original = pi.current_version
    pi.current_version = function()
      return "0.11.0"
    end
    local supported, current = pi.is_supported()
    pi.current_version = original
    assert.is_false(supported)
    assert.equal("0.11.0", current)
  end)
end)

describe("pi.ui2", function()
  it("exposes the experimental ui2 module on 0.12.5", function()
    local available, reason = require("pi.ui2").is_available()
    assert.is_true(available, reason)
  end)

  it("enables without error", function()
    local enabled = require("pi.ui2").enable()
    assert.is_true(enabled)
  end)
end)

describe("pi.setup", function()
  it("is idempotent and enables ui2", function()
    local first = pi.setup()
    local second = pi.setup()
    assert.equal(first, second)
    assert.is_true(pi.ui2_enabled)
  end)

  it("reports status", function()
    assert.matches("neovim%-pi", pi.status())
  end)
end)
