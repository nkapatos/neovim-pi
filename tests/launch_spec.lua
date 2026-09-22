local launch = require("pi.launch")

--- @param list string[]
--- @param value string
--- @return boolean
local function has(list, value)
  return vim.list_contains(list, value)
end

--- @param list string[]
--- @param flag string
--- @return string|nil
local function value_after(list, flag)
  for i, v in ipairs(list) do
    if v == flag then
      return list[i + 1]
    end
  end
  return nil
end

describe("pi.launch argv", function()
  it("builds the minimal command", function()
    assert.same({ "pi", "--mode", "rpc" }, launch.argv({ session = "new" }))
    assert.same({ "pi", "--mode", "rpc" }, launch.argv({}))
  end)

  it("maps model/thinking/session/name/trust flags", function()
    local argv = launch.argv({
      provider = "deepseek",
      model = "deepseek-flash",
      thinking = "high",
      session = "continue",
      name = "work",
      approve = "approve",
    })
    assert.same({
      "pi",
      "--mode",
      "rpc",
      "--provider",
      "deepseek",
      "--model",
      "deepseek-flash",
      "--thinking",
      "high",
      "--continue",
      "--name",
      "work",
      "--approve",
    }, argv)
  end)

  it("handles session variants", function()
    assert.is_true(has(launch.argv({ session = "none" }), "--no-session"))
    assert.is_true(has(launch.argv({ session = "resume" }), "--resume"))
    local argv = launch.argv({ session = "/tmp/s.jsonl" })
    assert.equal("/tmp/s.jsonl", value_after(argv, "--session"))
  end)

  it("maps tool and resource flags", function()
    local argv = launch.argv({
      tools = { "read", "bash" },
      exclude_tools = "write",
      no_builtin_tools = true,
      no_extensions = true,
      extensions = { "./a.ts", "./b.ts" },
    })
    assert.equal("read,bash", value_after(argv, "--tools"))
    assert.equal("write", value_after(argv, "--exclude-tools"))
    assert.is_true(has(argv, "--no-builtin-tools"))
    assert.is_true(has(argv, "--no-extensions"))
    assert.equal(2, (has(argv, "./a.ts") and 1 or 0) + (has(argv, "./b.ts") and 1 or 0))
  end)

  it("appends raw extras", function()
    local argv = launch.argv({ extra = { "--verbose", "--offline" } })
    assert.equal("--verbose", argv[#argv - 1])
    assert.equal("--offline", argv[#argv])
  end)

  it("describes a shell-quoted command", function()
    local desc = launch.describe({ model = "deepseek-flash" })
    assert.matches("^pi ", desc)
    assert.matches("--mode", desc)
    assert.matches("deepseek%-flash", desc)

    local quoted = launch.describe({ name = "my session" })
    assert.matches("'my session'", quoted)
  end)
end)

describe("pi.launch root", function()
  it("finds the root via markers", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. "/proj/sub", "p")
    vim.fn.writefile({}, tmp .. "/proj/sub/file.txt")
    vim.fn.mkdir(tmp .. "/proj/.git", "p")

    local root = launch.root(tmp .. "/proj/sub/file.txt", { ".git" })
    assert.equal("proj", vim.fn.fnamemodify(root, ":t"))
  end)

  it("falls back to the file's directory", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. "/loose", "p")
    vim.fn.writefile({}, tmp .. "/loose/file.txt")

    local root = launch.root(tmp .. "/loose/file.txt", { ".git" })
    assert.equal("loose", vim.fn.fnamemodify(root, ":t"))
  end)
end)

describe("pi.launch trust", function()
  it("reports explicit override modes", function()
    assert.equal("approve", launch.trust({ approve = "approve" }, "/tmp").mode)
    assert.equal("no-approve", launch.trust({ approve = "no-approve" }, "/tmp").mode)
    assert.equal("default", launch.trust({}, "/tmp").mode)
  end)

  it("detects project-local resources", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. "/proj/.pi", "p")
    vim.fn.mkdir(tmp .. "/plain", "p")

    assert.is_true(launch.trust({}, tmp .. "/proj").project_resources)
    assert.is_false(launch.trust({}, tmp .. "/plain").project_resources)
  end)
end)
