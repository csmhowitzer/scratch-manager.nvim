-- Tests for pad matching, toggle, delete and the scratch pad indicator
-- Uses a mocked snacks.nvim and real temp directories/files

local calls
local list_items = {}

local mock_scratch = setmetatable({
  open = function(opts)
    table.insert(calls, { kind = "open", opts = opts })
  end,
  list = function()
    return list_items
  end,
}, {
  __call = function(_, opts)
    table.insert(calls, { kind = "new", opts = opts })
  end,
})

package.loaded["snacks"] = {
  scratch = mock_scratch,
  util = {
    icon = function()
      return "x"
    end,
  },
}

local function normalize(path)
  return vim.fs.normalize(path)
end

describe("scratch-manager pads", function()
  local sm
  local tmp
  local original_cwd
  local original_confirm
  local notifications

  -- Create (and enter) a named buffer for a source file inside the temp project
  local function edit_source(relpath)
    local path = tmp .. "/" .. relpath
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, path)
    vim.api.nvim_set_current_buf(buf)
    return buf
  end

  -- Build a snacks-style scratch item, optionally backed by a real file
  local function pad(name, ft, opts)
    opts = opts or {}
    local file = tmp .. "/scratch/" .. name .. "." .. ft .. (opts.suffix or "")
    if opts.create ~= false then
      vim.fn.mkdir(tmp .. "/scratch", "p")
      vim.fn.writefile({ "note" }, file)
    end
    return {
      name = "Scratch Pad (" .. name .. ")",
      cwd = opts.cwd or tmp,
      branch = opts.branch,
      ft = ft,
      file = file,
    }
  end

  local function set_branch(branch)
    vim.fn.mkdir(tmp .. "/.git", "p")
    vim.fn.writefile({ "ref: refs/heads/" .. branch }, tmp .. "/.git/HEAD")
  end

  before_each(function()
    calls = {}
    list_items = {}
    notifications = {}
    tmp = normalize(vim.fn.resolve(vim.fn.tempname()))
    vim.fn.mkdir(tmp, "p")
    original_cwd = vim.fn.getcwd()
    vim.fn.chdir(tmp)

    original_confirm = vim.fn.confirm
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    package.loaded["scratch-manager"] = nil
    sm = require("scratch-manager")
  end)

  after_each(function()
    vim.fn.confirm = original_confirm
    vim.fn.chdir(original_cwd)
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(tmp, "rf")
  end)

  describe("before setup", function()
    it("toggle does not crash", function()
      edit_source("foo.lua")
      assert.has_no.errors(function()
        sm.toggle_scratch_pad()
      end)
      assert.equals("new", calls[1].kind)
    end)

    it("status returns an empty string", function()
      assert.equals("", sm.status())
    end)
  end)

  describe("matching", function()
    before_each(function()
      sm.setup({ enable_keymaps = false })
    end)

    it("matches pads by Neovim's cwd, not the buffer's directory", function()
      list_items = { pad("bar.lua", "lua") }
      edit_source("lua/deep/nested/bar.lua")
      sm.refresh_indicator()
      assert.equals(1, vim.b.scratch_manager_pads)
    end)

    it("does not match pads from another working directory", function()
      list_items = { pad("bar.lua", "lua", { cwd = "/somewhere/else" }) }
      edit_source("bar.lua")
      sm.refresh_indicator()
      assert.equals(0, vim.b.scratch_manager_pads)
    end)

    it("only matches pads keyed on the current branch", function()
      set_branch("main")
      list_items = { pad("bar.lua", "lua", { branch = "other" }) }
      edit_source("bar.lua")
      sm.refresh_indicator()
      assert.equals(0, vim.b.scratch_manager_pads)

      list_items = { pad("bar.lua", "lua", { branch = "main" }) }
      sm.refresh_indicator()
      assert.equals(1, vim.b.scratch_manager_pads)
    end)

    it("counts pads of every filetype for the indicator", function()
      list_items = { pad("bar.lua", "lua"), pad("bar.lua", "markdown") }
      edit_source("bar.lua")
      sm.refresh_indicator()
      assert.equals(2, vim.b.scratch_manager_pads)
    end)
  end)

  describe("toggle", function()
    before_each(function()
      sm.setup({ enable_keymaps = false })
    end)

    it("opens the pad with the requested filetype", function()
      local lua_pad = pad("bar.lua", "lua")
      local md_pad = pad("bar.lua", "markdown")
      list_items = { lua_pad, md_pad }
      edit_source("src/bar.lua")

      sm.toggle_scratch_pad("markdown")
      assert.equals("open", calls[1].kind)
      assert.equals(md_pad.file, calls[1].opts.file)

      sm.toggle_scratch_pad()
      assert.equals(lua_pad.file, calls[2].opts.file)
    end)

    it("creates a new pad when none matches", function()
      list_items = { pad("bar.lua", "lua") }
      edit_source("src/bar.lua")
      sm.toggle_scratch_pad("markdown")
      assert.equals("new", calls[1].kind)
      assert.equals("markdown", calls[1].opts.ft)
    end)

    it("soft-wraps the scratch window by default, and not when wrap = false", function()
      edit_source("bar.lua")
      sm.toggle_scratch_pad("markdown")
      assert.is_true(calls[1].opts.win.wo.wrap)
      assert.is_true(calls[1].opts.win.wo.linebreak)

      sm.setup({ enable_keymaps = false, wrap = false })
      sm.toggle_scratch_pad("markdown")
      assert.is_false(calls[2].opts.win.wo.wrap)
    end)

    it("remembers which file a pad was opened from (for C# project references)", function()
      local original_open = mock_scratch.open
      local root = vim.fn.stdpath("data") .. "/scratch"
      vim.fn.mkdir(root, "p")
      local pad_file = root .. "/pad_source_test.cs"
      mock_scratch.open = function(opts)
        table.insert(calls, { kind = "open", opts = opts })
        vim.cmd.edit(vim.fn.fnameescape(pad_file)) -- like snacks: the pad becomes current
      end
      local cs_pad = pad("Invoice.cs", "cs")
      cs_pad.file = pad_file
      list_items = { cs_pad }
      local src = edit_source("src/Billing/Invoice.cs")
      local src_name = vim.api.nvim_buf_get_name(src)

      sm.toggle_scratch_pad()
      mock_scratch.open = original_open
      assert.equals(src_name, vim.b.scratch_manager_source)
      assert.equals(src_name, require("scratch-manager.store").get("pad_sources", vim.fs.normalize(pad_file)))
    end)

    it("closes the pad when toggled from inside it", function()
      local lua_pad = pad("bar.lua", "lua")
      list_items = { lua_pad }
      vim.cmd.edit(vim.fn.fnameescape(lua_pad.file))

      sm.toggle_scratch_pad()
      assert.equals(1, #calls)
      assert.equals("open", calls[1].kind)
      assert.equals(lua_pad.file, calls[1].opts.file)
    end)
  end)

  describe("delete", function()
    before_each(function()
      sm.setup({ enable_keymaps = false })
    end)

    it("deletes the pad for the source buffer after confirmation", function()
      local lua_pad = pad("bar.lua", "lua")
      list_items = { lua_pad }
      edit_source("lua/deep/bar.lua")
      vim.fn.confirm = function()
        return 1
      end

      sm.delete_current_scratch_pad()
      assert.equals(0, vim.fn.filereadable(lua_pad.file))
    end)

    it("keeps the pad when the confirmation is declined", function()
      local lua_pad = pad("bar.lua", "lua")
      list_items = { lua_pad }
      edit_source("bar.lua")
      vim.fn.confirm = function()
        return 2
      end

      sm.delete_current_scratch_pad()
      assert.equals(1, vim.fn.filereadable(lua_pad.file))
    end)

    it("deletes the pad from inside it and wipes its buffer", function()
      local lua_pad = pad("bar.lua", "lua")
      list_items = { lua_pad }
      vim.cmd.edit(vim.fn.fnameescape(lua_pad.file))
      local buf = vim.api.nvim_get_current_buf()
      vim.fn.confirm = function()
        return 1
      end

      sm.delete_current_scratch_pad()
      assert.equals(0, vim.fn.filereadable(lua_pad.file))
      assert.is_false(vim.api.nvim_buf_is_valid(buf))
    end)

    it("notifies when there is nothing to delete", function()
      edit_source("bar.lua")
      vim.fn.confirm = function()
        error("should not prompt")
      end

      sm.delete_current_scratch_pad()
      assert.truthy(notifications[#notifications].msg:find("No scratch pad"))
    end)
  end)

  describe("autosave", function()
    -- Open a pad file under the scratch root (where snacks keeps pads) and make it unsaved
    local function edit_unsaved_pad()
      local root = vim.fn.stdpath("data") .. "/scratch"
      assert.truthy(root:find(vim.env.SCRATCH_MANAGER_TEST_HOME, 1, true)) -- never the real dir
      vim.fn.mkdir(root, "p")
      local file = root .. "/autosave_test.cs"
      vim.cmd.edit(vim.fn.fnameescape(file))
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Console.WriteLine(1);" })
      assert.is_true(vim.bo.modified)
      return file
    end

    it("writes a pad after a change, so it never prompts to save", function()
      sm.setup({ enable_keymaps = false })
      local file = edit_unsaved_pad()
      vim.cmd("doautocmd TextChanged")
      assert.is_false(vim.bo.modified)
      assert.same({ "Console.WriteLine(1);" }, vim.fn.readfile(file))
    end)

    it("writes a pad when leaving insert mode or the buffer", function()
      sm.setup({ enable_keymaps = false })
      local file = edit_unsaved_pad()
      vim.cmd("doautocmd InsertLeave")
      assert.is_false(vim.bo.modified)

      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })
      vim.cmd("doautocmd BufLeave")
      assert.same({ "changed" }, vim.fn.readfile(file))
    end)

    it("leaves normal files alone", function()
      sm.setup({ enable_keymaps = false })
      edit_source("bar.lua")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x" })
      vim.cmd("doautocmd TextChanged")
      assert.is_true(vim.bo.modified)
      vim.bo.modified = false
    end)

    it("can be turned off", function()
      sm.setup({ enable_keymaps = false, autosave = false })
      edit_unsaved_pad()
      vim.cmd("doautocmd TextChanged")
      assert.is_true(vim.bo.modified)
      vim.bo.modified = false
    end)
  end)

  describe("indicator", function()
    it("shows the icon only when the buffer has a pad", function()
      sm.setup({ enable_keymaps = false, indicator = { icon = "P" } })
      edit_source("bar.lua")
      sm.refresh_indicator()
      assert.equals("", sm.status())

      list_items = { pad("bar.lua", "markdown") }
      sm.refresh_indicator()
      assert.equals("P", sm.status())

      list_items = { pad("bar.lua", "markdown"), pad("bar.lua", "markdown", { suffix = ".2" }) }
      sm.refresh_indicator()
      assert.equals("P 2", sm.status())
    end)

    it("shows separate notes and code icons", function()
      sm.setup({ enable_keymaps = false, indicator = { icon = "N", code_icon = "C" } })
      edit_source("bar.lua")

      list_items = { pad("bar.lua", "lua") }
      sm.refresh_indicator()
      assert.equals("C", sm.status())

      list_items = { pad("bar.lua", "markdown"), pad("bar.lua", "lua"), pad("bar.lua", "python") }
      sm.refresh_indicator()
      assert.equals("N C 2", sm.status())
      assert.same({ notes = 1, code = 2, db = 0 }, vim.b.scratch_manager_pad_kinds)
    end)

    it("updates on BufEnter", function()
      sm.setup({ enable_keymaps = false, indicator = { icon = "P" } })
      list_items = { pad("bar.lua", "markdown") }
      edit_source("bar.lua")
      vim.cmd("doautocmd BufEnter")
      vim.wait(200, function()
        return sm.status() ~= ""
      end)
      assert.equals("P", sm.status())
    end)

    it("updates when a window closes (snacks closes toggled pads without BufEnter)", function()
      sm.setup({ enable_keymaps = false, indicator = { icon = "P" } })
      edit_source("bar.lua")
      sm.refresh_indicator()
      assert.equals("", sm.status())

      list_items = { pad("bar.lua", "markdown") }
      vim.cmd("vsplit | close")
      vim.wait(200, function()
        return sm.status() ~= ""
      end)
      assert.equals("P", sm.status())
    end)

    it("ignores special buffers", function()
      sm.setup({ enable_keymaps = false })
      list_items = { pad("bar.lua", "lua") }
      local buf = edit_source("bar.lua")
      vim.bo[buf].buftype = "nofile"
      sm.refresh_indicator()
      assert.equals(0, vim.b.scratch_manager_pads)
    end)

    it("notifies once per buffer when enabled", function()
      sm.setup({ enable_keymaps = false, indicator = { notify = true } })
      list_items = { pad("bar.lua", "lua") }
      edit_source("bar.lua")
      sm.refresh_indicator()
      sm.refresh_indicator()
      local count = 0
      for _, n in ipairs(notifications) do
        if n.msg:find("Scratch pad available") then
          count = count + 1
        end
      end
      assert.equals(1, count)
    end)

    describe("floating badge", function()
      local badge = require("scratch-manager.badge")

      after_each(function()
        badge.hide()
      end)

      it("is off by default", function()
        sm.setup({ enable_keymaps = false })
        list_items = { pad("bar.lua", "lua") }
        edit_source("bar.lua")
        sm.refresh_indicator()
        assert.is_nil(badge.get_win())
      end)

      it("shows the icon in a bordered float when the buffer has a pad", function()
        sm.setup({ enable_keymaps = false, indicator = { icon = "P", float = true } })
        list_items = { pad("bar.lua", "markdown") }
        edit_source("bar.lua")
        sm.refresh_indicator()

        local win = badge.get_win()
        assert.is_not_nil(win)
        local buf = vim.api.nvim_win_get_buf(win)
        assert.same({ " P " }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        local cfg = vim.api.nvim_win_get_config(win)
        assert.equals("editor", cfg.relative)
        assert.equals(vim.o.columns - 3 - 3, cfg.col) -- width 3, 2 border cells + 1 margin
        -- the badge must not steal focus
        assert.is_false(badge.is_badge_win())
      end)

      it("hides when the buffer has no pad", function()
        sm.setup({ enable_keymaps = false, indicator = { float = true } })
        list_items = { pad("bar.lua", "lua") }
        edit_source("bar.lua")
        sm.refresh_indicator()
        assert.is_not_nil(badge.get_win())

        list_items = {}
        sm.refresh_indicator()
        assert.is_nil(badge.get_win())
      end)

      it("stays open when focused by a click, and opens the pad from the source window", function()
        sm.setup({ enable_keymaps = false, indicator = { float = true } })
        local lua_pad = pad("bar.lua", "lua")
        list_items = { lua_pad }
        local src_win = vim.api.nvim_get_current_win()
        edit_source("bar.lua")
        sm.refresh_indicator()

        -- a mouse click focuses the badge, which fires BufEnter for the badge buffer
        vim.api.nvim_set_current_win(badge.get_win())
        vim.cmd("doautocmd BufEnter")
        assert.is_not_nil(badge.get_win())

        sm.open_pad_from_badge()
        assert.equals(src_win, vim.api.nvim_get_current_win())
        assert.equals("open", calls[#calls].kind)
        assert.equals(lua_pad.file, calls[#calls].opts.file)
      end)

      it("keeps the icon centered after the cursor moved onto it (sidescrolloff)", function()
        vim.o.sidescrolloff = 8 -- LazyVim default
        sm.setup({ enable_keymaps = false, indicator = { float = true, icon = "P" } })
        list_items = { pad("bar.lua", "markdown") }
        edit_source("bar.lua")
        sm.refresh_indicator()

        -- a click leaves the cursor on the icon
        vim.api.nvim_win_set_cursor(badge.get_win(), { 1, 2 })
        badge.hide()
        sm.refresh_indicator()

        local view = vim.api.nvim_win_call(badge.get_win(), vim.fn.winsaveview)
        assert.equals(0, view.leftcol)
        vim.o.sidescrolloff = 0
      end)

      it("grows into the pad before opening it when animate is on", function()
        sm.setup({ enable_keymaps = false, indicator = { float = true, animate = true } })
        local lua_pad = pad("bar.lua", "lua")
        list_items = { lua_pad }
        edit_source("bar.lua")
        sm.refresh_indicator()
        -- the growing box is the only zindex-50 float
        local function grow_boxes()
          return #vim.tbl_filter(function(w)
            return vim.api.nvim_win_get_config(w).zindex == 50
          end, vim.api.nvim_list_wins())
        end

        vim.api.nvim_set_current_win(badge.get_win())
        sm.open_pad_from_badge()
        assert.is_true(badge.is_animating())
        assert.equals(1, grow_boxes())
        assert.is_nil(badge.get_win()) -- the badge turns into the growing box
        assert.equals(0, #calls) -- the pad opens after the animation

        vim.wait(1000, function()
          return #calls > 0
        end)
        assert.is_false(badge.is_animating())
        assert.equals(lua_pad.file, calls[1].opts.file)
        assert.equals(0, grow_boxes())
      end)

      it("shows a notes badge in the corner and a green code badge to its left", function()
        sm.setup({ enable_keymaps = false, indicator = { float = true, icon = "N", code_icon = "C" } })
        list_items = { pad("bar.lua", "markdown"), pad("bar.lua", "lua") }
        edit_source("bar.lua")
        sm.refresh_indicator()

        local notes, code = badge.get_win("notes"), badge.get_win("code")
        assert.is_not_nil(notes)
        assert.is_not_nil(code)
        local notes_cfg, code_cfg = vim.api.nvim_win_get_config(notes), vim.api.nvim_win_get_config(code)
        assert.equals(vim.o.columns - 1 - 5, notes_cfg.col) -- 3 wide + 2 border, 1 cell margin
        assert.equals(notes_cfg.col - 1 - 5, code_cfg.col) -- 1 cell gap to its left
        assert.truthy(vim.wo[notes].winhighlight:find("FloatBorder:ScratchManagerBorder"))
        assert.truthy(vim.wo[code].winhighlight:find("FloatBorder:ScratchManagerCodeBorder"))

        -- only a code pad: the code badge moves into the corner
        list_items = { pad("bar.lua", "lua") }
        sm.refresh_indicator()
        assert.is_nil(badge.get_win("notes"))
        assert.equals(vim.o.columns - 1 - 5, vim.api.nvim_win_get_config(badge.get_win("code")).col)
      end)

      it("opens the pad of the clicked kind", function()
        sm.setup({ enable_keymaps = false, indicator = { float = true } })
        local md_pad, lua_pad = pad("bar.lua", "markdown"), pad("bar.lua", "lua")
        list_items = { md_pad, lua_pad }
        edit_source("bar.lua")
        sm.refresh_indicator()

        vim.api.nvim_set_current_win(badge.get_win("code"))
        sm.open_pad_from_badge("code")
        assert.equals(lua_pad.file, calls[#calls].opts.file)

        sm.refresh_indicator()
        vim.api.nvim_set_current_win(badge.get_win("notes"))
        sm.open_pad_from_badge("notes")
        assert.equals(md_pad.file, calls[#calls].opts.file)
      end)

      it("gives notes, code and DB pads their own border groups (gold, purple, green)", function()
        sm.setup({ enable_keymaps = false })
        edit_source("bar.lua")
        sm.toggle_scratch_pad()
        assert.truthy(calls[1].opts.win.wo.winhighlight:find("FloatBorder:ScratchManagerCodeBorder"))
        sm.toggle_scratch_pad("markdown")
        assert.truthy(calls[2].opts.win.wo.winhighlight:find("FloatBorder:ScratchManagerBorder,"))
        sm.toggle_scratch_pad("sql")
        assert.truthy(calls[3].opts.win.wo.winhighlight:find("FloatBorder:ScratchManagerDbBorder"))

        assert.equals("#cba6f7", string.format("#%06x", vim.api.nvim_get_hl(0, { name = "ScratchManagerCodeBorder" }).fg))
        assert.equals("#a6d189", string.format("#%06x", vim.api.nvim_get_hl(0, { name = "ScratchManagerDbBorder" }).fg))
      end)

      it("shows a DB badge to the left of the code badge", function()
        sm.setup({ enable_keymaps = false, indicator = { float = true, icon = "N", code_icon = "C", db_icon = "D" } })
        list_items = { pad("bar.lua", "markdown"), pad("bar.lua", "lua"), pad("bar.lua", "sql") }
        edit_source("bar.lua")
        sm.refresh_indicator()

        assert.equals("N C D", sm.status())
        local code_col = vim.api.nvim_win_get_config(badge.get_win("code")).col
        local db = badge.get_win("db")
        assert.equals(code_col - 1 - 5, vim.api.nvim_win_get_config(db).col)
        assert.truthy(vim.wo[db].winhighlight:find("FloatBorder:ScratchManagerDbBorder"))

        vim.api.nvim_set_current_win(db)
        sm.open_pad_from_badge("db")
        assert.equals("sql", calls[#calls].opts.ft)
      end)

      it("toggles a DB pad with =q, separate from == and =c", function()
        sm.setup({})
        edit_source("bar.lua")
        vim.api.nvim_feedkeys("=q", "x", false)
        assert.equals("sql", calls[1].opts.ft)
        assert.equals("<cr>", calls[1].opts.win.keys.run[1])
        assert.equals("<leader>dc", calls[1].opts.win.keys.connection[1])
      end)

      it("adds the run key only to C# pads", function()
        sm.setup({ enable_keymaps = false })
        edit_source("Program.cs")
        sm.toggle_scratch_pad()
        assert.equals("cs", calls[1].opts.ft)
        assert.equals("<cr>", calls[1].opts.win.keys.run[1])

        sm.toggle_scratch_pad("markdown")
        assert.is_nil(calls[2].opts.win.keys)

        sm.setup({ enable_keymaps = false, run = { cs = { enabled = false } } })
        sm.toggle_scratch_pad()
        assert.is_nil(calls[3].opts.win.keys)
      end)
    end)

    it("does not register autocmds when disabled", function()
      sm.setup({ enable_keymaps = false, indicator = { enabled = false } })
      assert.equals(0, #vim.api.nvim_get_autocmds({ group = "ScratchManagerIndicator" }))
    end)
  end)
end)
