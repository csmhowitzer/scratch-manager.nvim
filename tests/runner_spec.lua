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

  -- Wait until the output window shows something other than the "Running…" placeholder
  local function wait_for_output()
    vim.wait(5000, function()
      local w = runner._output.win
      if not (w and vim.api.nvim_win_is_valid(w)) then
        return false
      end
      local first = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, 1, false)[1]
      return first ~= "Running…"
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
    assert.same({ 'Console.WriteLine("hi");', "// second line" }, lines)
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
    assert.equals(30, vim.fn.line("w$", w))
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
