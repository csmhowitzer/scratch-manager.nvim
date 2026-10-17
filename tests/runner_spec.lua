-- Tests for the C# scratch pad runner (uses stand-in commands instead of dotnet)

describe("scratch-manager.runner", function()
  local runner = require("scratch-manager.runner")
  local tmp

  -- Open a named pad-like buffer in a window and return it
  local function pad_buffer(lines)
    tmp = vim.fn.tempname()
    vim.cmd.edit(vim.fn.fnameescape(tmp .. ".cs"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    return vim.api.nvim_get_current_buf()
  end

  -- Wait for the finished run: only the final title carries the run time ("· 12ms")
  local function wait_for_output()
    vim.wait(5000, function()
      local w = runner._output.win
      if not (w and vim.api.nvim_win_is_valid(w)) then
        return false
      end
      return vim.inspect(vim.api.nvim_win_get_config(w).title):find("%d+ms") ~= nil
    end)
    local w = runner._output.win
    return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false), vim.api.nvim_win_get_config(w)
  end

  after_each(function()
    runner.close_output()
    vim.cmd("silent! %bwipeout!")
  end)

  it("uses a stable work directory per pad", function()
    assert.equals(runner.work_dir("/a/pad.cs"), runner.work_dir("/a/pad.cs"))
    assert.are_not.equal(runner.work_dir("/a/pad.cs"), runner.work_dir("/b/pad.cs"))
  end)

  it("runs the pad source and shows the output", function()
    local buf = pad_buffer({ 'Console.WriteLine("hi");', "// second line" })
    runner.run_csharp(buf, { cmd = { "cat" } }) -- cat echoes the source file back

    local lines, cfg = wait_for_output()
    assert.same({ "#line 1", 'Console.WriteLine("hi");', "// second line" }, lines)
    assert.truthy(vim.inspect(cfg.title):find("ok"))
    -- the source is written to scratch.cs in the pad's work directory
    assert.equals(1, vim.fn.filereadable(runner.work_dir(vim.api.nvim_buf_get_name(buf)) .. "/scratch.cs"))
  end)

  it("shows the exit code when the run fails", function()
    local buf = pad_buffer({ "broken" })
    runner.run_csharp(buf, { cmd = { "false" } })

    local lines, cfg = wait_for_output()
    assert.same({ "(no output)" }, lines)
    assert.truthy(vim.inspect(cfg.title):find("exit 1"))
  end)

  it("passes PublishAot=false by default (reflection-based JSON works)", function()
    local seen
    local system = vim.system
    vim.system = function(cmd, _, on_exit)
      seen = cmd
      on_exit({ code = 0, stdout = "", stderr = "" })
    end
    local executable = vim.fn.executable
    vim.fn.executable = function()
      return 1
    end
    runner.run_csharp(pad_buffer({ "x" }), {})
    vim.system, vim.fn.executable = system, executable
    wait_for_output() -- let the scheduled result land before the next test

    assert.same({ "dotnet", "run", "-p:PublishAot=false" }, vim.list_slice(seen, 1, 3))
    assert.truthy(seen[4]:find("scratch.cs$"))
  end)

  it("shows the end of long output (results come after build warnings)", function()
    local source = {}
    for i = 1, 30 do
      source[i] = "line " .. i
    end
    local buf = pad_buffer(source)
    runner.run_csharp(buf, { cmd = { "cat" }, max_height = 5 })
    wait_for_output()
    local w = runner._output.win
    assert.equals(5, vim.api.nvim_win_get_height(w))
    assert.equals(31, vim.fn.line("w$", w)) -- "#line 1" + 30 source lines echoed by cat
  end)

  describe("project reference (#:project)", function()
    local root

    -- A source file inside src/Billing with Billing.csproj next to it, and a pad opened from it
    local function pad_from_project_file(lines)
      root = vim.fn.tempname()
      vim.fn.mkdir(root .. "/src/Billing/Models", "p")
      vim.fn.writefile({ "<Project />" }, root .. "/src/Billing/Billing.csproj")
      local buf = pad_buffer(lines)
      vim.b[buf].scratch_manager_source = root .. "/src/Billing/Models/Invoice.cs"
      return buf
    end

    after_each(function()
      vim.fn.delete(root, "rf")
    end)

    it("finds the nearest .csproj above the pad's source file", function()
      local buf = pad_from_project_file({ "x" })
      assert.equals(root .. "/src/Billing/Billing.csproj", runner.find_project(buf))
    end)

    it("references it at run time without changing the pad, keeping line numbers", function()
      local buf = pad_from_project_file({ "using Billing;", "Console.WriteLine(1);" })
      runner.run_csharp(buf, { cmd = { "cat" } })
      local lines, cfg = wait_for_output()
      assert.same({ "#:project " .. root .. "/src/Billing/Billing.csproj", "#line 1", "using Billing;", "Console.WriteLine(1);" }, lines)
      assert.truthy(vim.inspect(cfg.title):find("Billing.csproj"))
      assert.same({ "using Billing;", "Console.WriteLine(1);" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it("leaves pads with their own #:project alone, and can be turned off", function()
      local buf = pad_from_project_file({ "#:project ../Other/Other.csproj", "x" })
      runner.run_csharp(buf, { cmd = { "cat" } })
      assert.same({ "#:project ../Other/Other.csproj", "#line 1", "", "x" }, (wait_for_output()))
      runner.close_output()

      local buf2 = pad_from_project_file({ "y" })
      runner.run_csharp(buf2, { cmd = { "cat" }, project = false })
      assert.same({ "#line 1", "y" }, (wait_for_output()))
    end)

    it("uses the persisted source when the pad buffer has none", function()
      local buf = pad_from_project_file({ "x" })
      local source = vim.b[buf].scratch_manager_source
      vim.b[buf].scratch_manager_source = nil
      assert.is_nil(runner.find_project(buf))
      require("scratch-manager.store").set("pad_sources", vim.api.nvim_buf_get_name(buf), source)
      assert.equals(root .. "/src/Billing/Billing.csproj", runner.find_project(buf))
    end)
  end)

  describe("compose (what gets compiled)", function()
    local pad = {
      "#:package Humanizer@2.14.1", -- 1
      "using Billing;", --               2
      "using static System.Math;", --    3
      "", --                             4
      "var a = 1;", --                   5
      "using var stream = Open();", --   6 (a statement, not a directive)
      "Console.WriteLine(a);", --        7
    }

    it("hoists #: directives (plus the project) and keeps line numbers for the whole pad", function()
      local compiled, usings = runner.compose(pad, nil, "/p/Billing.csproj")
      assert.same({
        "#:project /p/Billing.csproj", "#:package Humanizer@2.14.1", "#line 1",
        "", "using Billing;", "using static System.Math;", "", "var a = 1;", "using var stream = Open();", "Console.WriteLine(a);",
      }, compiled)
      assert.equals(0, usings)
    end)

    it("adds the header's using directives to a selection, tagged with their pad lines", function()
      local compiled, usings = runner.compose(pad, { first = 6, last = 7 }, nil)
      assert.same({
        "#:package Humanizer@2.14.1",
        "#line 2", "using Billing;",
        "#line 3", "using static System.Math;",
        "#line 6", "using var stream = Open();", "Console.WriteLine(a);",
      }, compiled)
      assert.equals(2, usings)
    end)

    it("does not duplicate using lines that are already selected", function()
      local compiled, usings = runner.compose(pad, { first = 3, last = 5 }, nil)
      assert.same({ "#:package Humanizer@2.14.1", "#line 2", "using Billing;", "#line 3", "using static System.Math;", "", "var a = 1;" }, compiled)
      assert.equals(1, usings)
    end)
  end)

  it("says what ran in the title for a selection", function()
    local buf = pad_buffer({ "using System.Text;", "", "var a = 1;", "Console.WriteLine(a);" })
    vim.cmd("normal! 3GVj")
    runner.run_csharp(buf, { cmd = { "cat" } })
    local lines, cfg = wait_for_output()
    assert.same({ "#line 1", "using System.Text;", "#line 3", "var a = 1;", "Console.WriteLine(a);" }, lines)
    assert.truthy(vim.inspect(cfg.title):find("lines 3–4 %+ 1 using line"))
  end)

  it("points compiler messages at the pad instead of the hidden work file", function()
    local buf = pad_buffer({ "int x = \"oops\";" })
    runner.run_csharp(buf, { cmd = { "sh", "-c", 'echo "$0(1,9): error CS0029: Cannot convert"; exit 1' } })
    local lines = wait_for_output()
    assert.same({ "pad(1,9): error CS0029: Cannot convert" }, lines)
  end)

  it("hides build warnings (noted in the title) unless show_warnings is set", function()
    local script = 'echo "Billing.csproj : warning NU1903: Package x has a vulnerability"; '
      .. 'echo "Foo.cs(76,34): warning CS0618: obsolete"; echo "1374.62"'
    local buf = pad_buffer({ "x" })
    runner.run_csharp(buf, { cmd = { "sh", "-c", script } })
    local lines, cfg = wait_for_output()
    assert.same({ "1374.62" }, lines)
    assert.truthy(vim.inspect(cfg.title):find("2 warnings hidden"))
    runner.close_output()

    runner.run_csharp(buf, { cmd = { "sh", "-c", script }, show_warnings = true })
    assert.equals(3, #(wait_for_output()))
  end)

  it("reports a missing command instead of running", function()
    local messages = {}
    local notify = vim.notify
    vim.notify = function(msg)
      table.insert(messages, msg)
    end
    runner.run_csharp(pad_buffer({ "x" }), { cmd = { "definitely-not-a-real-dotnet" } })
    vim.notify = notify

    assert.truthy(messages[1]:find("not found"))
    assert.is_nil(runner._output.win)
  end)

  it("anchors the output inside the pad window and closes it with q", function()
    local buf = pad_buffer({ "x" })
    local pad_win = vim.api.nvim_get_current_win()
    runner.run_csharp(buf, { cmd = { "cat" } })
    local _, cfg = wait_for_output()
    assert.equals("win", cfg.relative)
    assert.equals(pad_win, cfg.win)

    vim.api.nvim_set_current_win(runner._output.win)
    vim.api.nvim_feedkeys("q", "x", false)
    assert.is_nil(runner._output.win)
  end)
end)
