-- Language profiles: a language added with register() gets running, keys, help and health
-- without any plugin changes (the same path new languages like Python will take)

local calls = {}
package.loaded["snacks"] = {
  scratch = setmetatable({
    open = function(opts)
      table.insert(calls, opts)
    end,
    list = function()
      return {}
    end,
  }, {
    __call = function(_, opts)
      table.insert(calls, opts)
    end,
  }),
  util = {
    icon = function()
      return "x"
    end,
  },
}

describe("scratch-manager.languages", function()
  local languages = require("scratch-manager.languages")
  local runner = require("scratch-manager.runner")

  -- A stand-in language: `cat` "runs" the work file, echoing it back
  local function register_echo(extra)
    languages.register("echolang", vim.tbl_extend("force", {
      run = {
        title = "echo run",
        desc = "Run (echo)",
        file = "scratch.echo",
        inline = true,
        cmd = function(config)
          return config.cmd or { "cat" }
        end,
        hide_line = function(line)
          return line:match("^NOISE") ~= nil
        end,
      },
      help = function(info, h)
        return { { title = "Echo pad · " .. h.source_name(info) }, { p = "Runs with `cat`." } }
      end,
      health = function(report)
        report.ok("echolang ready")
      end,
    }, extra or {}))
  end

  local function pad_buffer(lines)
    vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname() .. ".echo"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    return vim.api.nvim_get_current_buf()
  end

  local function wait_for_output()
    vim.wait(5000, function()
      local w = runner._output.win
      return w and vim.api.nvim_win_is_valid(w)
        and vim.inspect(vim.api.nvim_win_get_config(w).title):find("✓ ok", 1, true) ~= nil
    end)
    local w = runner._output.win
    return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false), vim.api.nvim_win_get_config(w)
  end

  before_each(function()
    calls = {}
  end)

  after_each(function()
    runner.close_output()
    vim.cmd("silent! %bwipeout!")
  end)

  it("ships profiles for C#, SQL, Lua and markdown, and lists registered ones", function()
    register_echo()
    assert.same({ "cs", "sql", "lua", "markdown", "echolang" }, languages.known())
    assert.equals("db", languages.get("sql").kind)
    assert.equals("notes", languages.get("markdown").kind)
    assert.equals("code", languages.get("python").kind) -- no profile: defaults
  end)

  it("runs a registered language through the generic runner", function()
    register_echo()
    local buf = pad_buffer({ "hello", "NOISE: build chatter", "world" })
    runner.run(buf, "echolang", {})
    local lines, cfg = wait_for_output()
    assert.same({ "1 warning hidden", "hello", "world" }, lines)
    assert.truthy(vim.inspect(cfg.title):find("echo run · ✓ ok", 1, true))
    -- work files are kept per language
    assert.truthy(runner.work_dir(vim.api.nvim_buf_get_name(buf), "echolang"):find("/scratch%-manager/echolang/"))
  end)

  it("runs only a selection and shows inline value markers for any language", function()
    register_echo()
    local marker = string.char(30) .. "2" .. string.char(31) .. "42"
    local buf = pad_buffer({ "skip me", marker, "and me" })
    vim.cmd("normal! 2GV")
    runner.run(buf, "echolang", {})
    local lines = wait_for_output()
    assert.same({ "lines 2–2", "1 value shown inline (K on its line for the full value)" }, lines)
    local marks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
    assert.equals("  → 42", marks[1][4].virt_text[1][1])
  end)

  it("gives pads of a registered language a run key, help and a health line", function()
    register_echo()
    local sm = require("scratch-manager")
    sm.setup({ enable_keymaps = false })
    vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname() .. "/main.echo"))
    sm.toggle_scratch_pad("echolang")
    local keys = calls[1].win.keys
    assert.equals("Run (echo)", keys.run.desc)
    assert.equals("K", keys.value[1])

    local help = require("scratch-manager.help")
    local text = table.concat(help.render(help.blocks({ ft = "echolang", kind = "code", name = "main.echo", keymaps = {}, help_key = "=h" })), "\n")
    assert.truthy(text:find("Echo pad · main.echo", 1, true))
    assert.truthy(text:find("All pads", 1, true))

    local reported = {}
    languages.get("echolang").health({ ok = function(msg) table.insert(reported, msg) end })
    assert.same({ "echolang ready" }, reported)
  end)

  it("lets a profile add pad keys and an on_open hook", function()
    local opened = {}
    register_echo({
      keys = function()
        return { extra = { "gx", function() end, desc = "Extra" } }
      end,
      on_open = function(bufnr)
        table.insert(opened, bufnr)
      end,
    })
    local sm = require("scratch-manager")
    sm.setup({ enable_keymaps = false })
    vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname() .. "/main.echo"))
    sm.toggle_scratch_pad("echolang")
    assert.equals("Extra", calls[1].win.keys.extra.desc)

    -- a pad buffer under the scratch root with this filetype triggers on_open once
    local root = vim.fn.stdpath("data") .. "/scratch"
    vim.fn.mkdir(root, "p")
    vim.cmd.edit(vim.fn.fnameescape(root .. "/hook_test.echo"))
    vim.bo.filetype = "echolang"
    vim.bo.filetype = "echolang"
    assert.equals(1, #opened)
  end)
end)
