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

    it("applies a language's window options to its pads (C#: conceal for the #:project path)", function()
      sm.setup({ enable_keymaps = false })
      edit_source("Program.cs")
      sm.toggle_scratch_pad()
      assert.equals(2, calls[1].opts.win.wo.conceallevel)
      sm.toggle_scratch_pad("markdown")
      assert.is_nil(calls[2].opts.win.wo.conceallevel)
    end)

    it("wraps notes pads but not code or DB pads by default, with <M-z> to toggle", function()
      edit_source("bar.lua")
      sm.toggle_scratch_pad("markdown")
      sm.toggle_scratch_pad("lua")
      sm.toggle_scratch_pad("sql")
      assert.is_true(calls[1].opts.win.wo.wrap)
      assert.is_false(calls[2].opts.win.wo.wrap)
      assert.is_false(calls[3].opts.win.wo.wrap)
      assert.is_false(calls[3].opts.win.wo.linebreak)

      -- per-kind override, and the toggle key flips the window it runs in
      sm.setup({ enable_keymaps = false, wrap = { code = true } })
      sm.toggle_scratch_pad("lua")
      assert.is_true(calls[4].opts.win.wo.wrap)
      local key = calls[4].opts.win.keys.wrap
      assert.equals("<M-z>", key[1])
      local win = vim.api.nvim_get_current_win()
      vim.wo[win].wrap = false
      key[2]({ win = win })
      assert.is_true(vim.wo[win].wrap)
      assert.is_true(vim.wo[win].linebreak)
      key[2]({ win = win })
      assert.is_false(vim.wo[win].wrap)
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

    it("cycles the pad size with =w: a third, two thirds, nearly full, back", function()
      vim.o.columns = 150
      sm.setup({ enable_keymaps = false })
      edit_source("bar.lua")
      sm.toggle_scratch_pad("lua")
      local first = calls[1].opts.win
      assert.equals(50, first.width)
      assert.equals(100, first.col)

      local win = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false,
        { relative = "editor", row = 1, col = first.col, width = first.width, height = 10 })
      local key = first.keys.size
      assert.equals("=w", key[1])
      key[2]({ win = win, buf = vim.api.nvim_get_current_buf() })
      assert.equals(100, vim.api.nvim_win_get_width(win)) -- two thirds, still on the right
      assert.equals(50, vim.api.nvim_win_get_config(win).col)
      key[2]({ win = win, buf = vim.api.nvim_get_current_buf() })
      assert.equals(150 - 7 * 2 - 2, vim.api.nvim_win_get_width(win)) -- nearly full, 5% margins
      assert.equals(7, vim.api.nvim_win_get_config(win).col)

      -- the size sticks for pads opened afterwards
      sm.toggle_scratch_pad("lua")
      assert.equals(150 - 7 * 2 - 2, calls[2].opts.win.width)
      key[2]({ win = win, buf = vim.api.nvim_get_current_buf() })
      assert.equals(50, vim.api.nvim_win_get_width(win))
      assert.equals(1, sm._pad_size())
      vim.api.nvim_win_close(win, true)
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

  describe("pad setup (language on_open)", function()
    it("runs once the pad has a window, not in Neovim's hidden autocmd window", function()
      sm.setup({ enable_keymaps = false })
      local seen = {}
      require("scratch-manager.languages").register("smtestdb", {
        kind = "db",
        on_open = function(bufnr)
          table.insert(seen, { win_type = vim.fn.win_gettype(), shown = #vim.fn.win_findbuf(bufnr) > 0 })
        end,
      })
      local root = vim.fn.stdpath("data") .. "/scratch"
      vim.fn.mkdir(root, "p")
      edit_source("bar.lua")
      -- like snacks: the filetype is set while the pad isn't shown (FileType runs in the autocmd window)
      local buf = vim.fn.bufadd(root .. "/deferred.smtestdb")
      vim.fn.bufload(buf)
      vim.bo[buf].filetype = "smtestdb"
      assert.same({}, seen)
      -- then the pad window opens
      vim.api.nvim_open_win(buf, true, { relative = "editor", row = 1, col = 1, width = 20, height = 5, border = "rounded" })
      vim.wait(200, function() return #seen > 0 end)
      assert.equals(1, #seen)
      assert.equals("popup", seen[1].win_type)
      assert.is_true(seen[1].shown)
    end)
  end)

  describe("flipping between pads", function()
    it("opens another kind of pad for the same source from inside a pad (==, =c, =q)", function()
      sm.setup({ enable_keymaps = false })
      local source = edit_source("bar.lua")
      local source_name = vim.api.nvim_buf_get_name(source)
      local lua_pad, md_pad = pad("bar.lua", "lua"), pad("bar.lua", "markdown")
      list_items = { lua_pad, md_pad }
      vim.cmd.edit(vim.fn.fnameescape(lua_pad.file))
      vim.b.scratch_manager_source = source_name

      sm.toggle_scratch_pad("markdown") -- == inside the code pad
      assert.equals(2, #calls)
      assert.equals(lua_pad.file, calls[1].opts.file) -- the code pad is closed (snacks toggles it)
      assert.equals(md_pad.file, calls[2].opts.file) -- and the notes pad opened
      assert.equals(source, vim.api.nvim_get_current_buf()) -- opened from the source file

      -- no DB pad yet: =q creates one for the source
      vim.cmd.edit(vim.fn.fnameescape(md_pad.file))
      vim.b.scratch_manager_source = source_name
      sm.toggle_scratch_pad("sql")
      assert.equals("new", calls[4].kind)
      assert.equals("sql", calls[4].opts.ft)
    end)

    it("still just closes the pad with its own kind's key, or when its source is unknown", function()
      sm.setup({ enable_keymaps = false })
      local lua_pad = pad("bar.lua", "lua")
      list_items = { lua_pad }
      vim.cmd.edit(vim.fn.fnameescape(lua_pad.file))
      vim.b.scratch_manager_source = tmp .. "/bar.lua"
      sm.toggle_scratch_pad() -- =c in a code pad
      assert.equals(1, #calls)

      vim.b.scratch_manager_source = nil
      sm.toggle_scratch_pad("markdown") -- source unknown: nothing to flip to
      assert.equals(2, #calls)
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

  describe("language servers on pads", function()
    -- A minimal in-process language server
    local function fake_server(name, bufnr)
      local id = vim.lsp.start({
        name = name,
        cmd = function()
          return {
            request = function(method, _, callback)
              if method == "initialize" then
                callback(nil, { capabilities = {} })
              else
                callback(nil, nil)
              end
              return true, 1
            end,
            notify = function() return true end,
            is_closing = function() return false end,
            terminate = function() end,
          }
        end,
        root_dir = tmp,
      }, { bufnr = bufnr })
      vim.wait(1000, function()
        local c = vim.lsp.get_client_by_id(id)
        return c ~= nil and c.initialized
      end)
      vim.wait(200) -- let the scheduled detach run
      return id
    end

    local function pad_buf(name)
      local root = vim.fn.stdpath("data") .. "/scratch"
      vim.fn.mkdir(root, "p")
      vim.cmd.edit(vim.fn.fnameescape(root .. "/" .. name))
      return vim.api.nvim_get_current_buf()
    end

    it("detaches servers from pads but keeps allowed ones and normal files", function()
      sm.setup({ enable_keymaps = false })
      local pad = pad_buf("lsp_test.cs")
      assert.is_true(vim.b[pad].scratch_manager_pad)
      -- the server must never be sent the pad: record what it receives
      local received = {}
      local roslyn = vim.lsp.start({
        name = "fake_roslyn",
        cmd = function()
          return {
            request = function(method, _, callback)
              callback(nil, method == "initialize" and { capabilities = { textDocumentSync = 1 } } or nil)
              return true, 1
            end,
            notify = function(method)
              table.insert(received, method)
              return true
            end,
            is_closing = function() return false end,
            terminate = function() end,
          }
        end,
        root_dir = tmp,
      }, { bufnr = pad })
      vim.wait(500)
      vim.api.nvim_buf_set_lines(pad, 0, -1, false, { "changed" })
      vim.wait(200)
      assert.is_false(vim.lsp.buf_is_attached(pad, roslyn))
      assert.is_nil(vim.tbl_contains(received, "textDocument/didOpen") or nil)
      assert.is_nil(vim.tbl_contains(received, "textDocument/didChange") or nil)

      local lua_pad = pad_buf("lsp_test.lua")
      local lua_ls = fake_server("lua_ls", lua_pad)
      assert.is_true(vim.lsp.buf_is_attached(lua_pad, lua_ls))

      local src = edit_source("Real.cs")
      local real = fake_server("fake_roslyn_2", src)
      assert.is_true(vim.lsp.buf_is_attached(src, real))
      assert.is_nil(vim.b[src].scratch_manager_pad)
    end)

    it("leaves servers alone with lsp.detach = false", function()
      sm.setup({ enable_keymaps = false, lsp = { detach = false } })
      local pad = pad_buf("lsp_keep.cs")
      local id = fake_server("fake_roslyn_3", pad)
      assert.is_true(vim.lsp.buf_is_attached(pad, id))
    end)
  end)

  describe("pad help (=h)", function()
    local help = require("scratch-manager.help")

    after_each(function()
      help.close()
    end)

    -- A buffer standing in for a pad of the given filetype, opened from `source`
    local function pad_buf(ft, source)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, tmp .. "/scratch/pad." .. ft)
      vim.bo[buf].filetype = ft
      vim.b[buf].scratch_manager_source = source
      vim.api.nvim_set_current_buf(buf)
      return buf
    end

    local function help_text()
      return table.concat(vim.api.nvim_buf_get_lines(help._state.buf, 0, -1, false), "\n")
    end

    it("adds =h to every pad, configurable or off", function()
      sm.setup({ enable_keymaps = false })
      edit_source("bar.lua")
      sm.toggle_scratch_pad("markdown")
      assert.equals("=h", calls[1].opts.win.keys.help[1])

      sm.setup({ enable_keymaps = false, keymaps = { pad_help = "g?" } })
      sm.toggle_scratch_pad("markdown")
      assert.equals("g?", calls[2].opts.win.keys.help[1])

      sm.setup({ enable_keymaps = false, keymaps = { pad_help = false } })
      sm.toggle_scratch_pad("markdown")
      assert.is_nil(calls[3].opts.win.keys.help)
    end)

    it("explains C# pads with this pad's project, selections and #: directives", function()
      sm.setup({ enable_keymaps = false })
      vim.fn.mkdir(tmp .. "/src/Billing", "p")
      vim.fn.writefile({ "<Project />" }, tmp .. "/src/Billing/Billing.csproj")
      local buf = pad_buf("cs", tmp .. "/src/Billing/Invoice.cs")
      sm.show_help(buf)

      local text = help_text()
      assert.truthy(text:find("C# scratch pad · Invoice.cs", 1, true))
      assert.truthy(text:find("Throwaway C# for Invoice.cs.", 1, true)) -- markers removed
      assert.truthy(text:find("reference to Billing.csproj", 1, true))
      assert.truthy(text:find("plus the using lines", 1, true))
      assert.truthy(text:find("│ #:package  │ <PackageReference>", 1, true)) -- aligned table
      assert.truthy(text:find("│ =q    │ DB pad (SQL)", 1, true))
      assert.is_nil(text:find("`", 1, true))
      assert.is_nil(text:find("**", 1, true))
      assert.equals(help._state.win, vim.api.nvim_get_current_win())
    end)

    it("shows a DB pad's remembered connection, or that the first run will ask", function()
      sm.setup({ enable_keymaps = false, run = { sql = { provider = false } } })
      local buf = pad_buf("sql", tmp .. "/Jobs.cs")
      sm.show_help(buf)
      assert.truthy(help_text():find("first run asks", 1, true))
      assert.truthy(help_text():find("No provider\n───────────", 1, true))

      require("scratch-manager.sql").set_connection_name(vim.api.nvim_buf_get_name(buf), "Dev SQL")
      sm.show_help(buf)
      assert.truthy(help_text():find("runs on Dev SQL", 1, true))
    end)

    it("renders inline code, bold, headings and tables with highlights", function()
      local text, ranges = help.inline("Run `dotnet run` for **Foo.cs** now")
      assert.equals("Run dotnet run for Foo.cs now", text)
      assert.same({ { 4, 14, "ScratchManagerHelpCode" }, { 19, 25, "ScratchManagerHelpBold" } }, ranges)

      local lines, hls = help.render({
        { title = "T" },
        { h = "Head" },
        { t = { { "Key", "Action" }, { "`<CR>`", "Run" } } },
      })
      assert.same({ "T", "━", "", "Head", "────", "╭──────┬────────╮", "│ Key  │ Action │", "├──────┼────────┤", "│ <CR> │ Run    │", "╰──────┴────────╯" }, lines)
      local groups = {}
      for _, h in ipairs(hls) do
        groups[h[4]] = true
      end
      assert.is_true(groups.ScratchManagerHelpTitle and groups.ScratchManagerHelpHeading and groups.ScratchManagerHelpCode)
    end)

    it("renders code examples with aligned values, and syntax colors when the parser exists", function()
      local lines, hls = help.render({ { lang = "lua", code = { { "local a = 1", "1" }, { "a", "x" }, "print(a)" } } })
      assert.same({ "    local a = 1  → 1", "    a            → x", "    print(a)" }, lines)
      local dump, syntax = 0, false
      for _, h in ipairs(hls) do
        dump = dump + (h[4] == "ScratchManagerDump" and 1 or 0)
        syntax = syntax or h[4] == "@keyword.lua"
      end
      assert.equals(2, dump)
      assert.is_true(syntax) -- lua's parser ships with Neovim

      -- unknown language: the whole line in the code color
      local _, plain = help.render({ { lang = "nolang", code = { "x" } } })
      assert.same({ { 0, 0, 5, "ScratchManagerHelpCode" } }, plain)
    end)

    it("closes with q", function()
      sm.setup({ enable_keymaps = false })
      sm.show_help(pad_buf("markdown", tmp .. "/notes.cs"))
      assert.truthy(help_text():find("Notes scratch pad", 1, true))
      vim.api.nvim_feedkeys("q", "x", false)
      assert.is_nil(help._state.win)
    end)
  end)

  describe("smart persistence", function()
    local store = require("scratch-manager.store")
    local root

    -- Show a pad file in a split with the given text (saved), from a source buffer
    local function open_pad(name, lines)
      root = vim.fn.stdpath("data") .. "/scratch"
      assert.truthy(root:find(vim.env.SCRATCH_MANAGER_TEST_HOME, 1, true)) -- never the real dir
      vim.fn.mkdir(root, "p")
      local file = normalize(root .. "/" .. name)
      vim.cmd.edit(vim.fn.fnameescape(tmp .. "/src/A.cs"))
      vim.cmd("split " .. vim.fn.fnameescape(file))
      vim.bo.bufhidden = "hide" -- like snacks
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.cmd("silent write")
      return file, vim.api.nvim_get_current_buf()
    end

    -- Close the pad's window and let the scheduled check run
    local function close_pad(bufnr)
      vim.cmd("close")
      vim.wait(200, function() return not vim.api.nvim_buf_is_valid(bufnr) end)
    end

    it("deletes a pad closed with nothing in it, and what was stored for it", function()
      sm.setup({ enable_keymaps = false })
      local file, bufnr = open_pad("blank.markdown", { "", "   ", "" })
      store.set("pad_sources", file, tmp .. "/src/A.cs")
      close_pad(bufnr)
      assert.equals(0, vim.fn.filereadable(file))
      assert.is_false(vim.api.nvim_buf_is_valid(bufnr))
      assert.is_nil(store.get("pad_sources", file))
    end)

    it("counts a C# pad with only using / #: lines as empty (the plugin adds those)", function()
      sm.setup({ enable_keymaps = false })
      local file, bufnr = open_pad("gen.cs", { "#:project /x/A.csproj", "using System.Text;", "" })
      close_pad(bufnr)
      assert.equals(0, vim.fn.filereadable(file))
    end)

    it("keeps pads with content, and every pad with smart_persistence = false", function()
      sm.setup({ enable_keymaps = false })
      local file, bufnr = open_pad("real.cs", { "using System.Text;", "", "var a = 1;" })
      close_pad(bufnr)
      assert.equals(1, vim.fn.filereadable(file))
      assert.is_true(vim.api.nvim_buf_is_valid(bufnr))

      sm.setup({ enable_keymaps = false, smart_persistence = false })
      local blank, blank_buf = open_pad("kept.markdown", { "" })
      close_pad(blank_buf)
      assert.equals(1, vim.fn.filereadable(blank))
    end)

    it("leaves a pad alone while another window still shows it", function()
      sm.setup({ enable_keymaps = false })
      local file, bufnr = open_pad("twice.markdown", { "" })
      vim.cmd("split")
      vim.cmd("close")
      vim.wait(100)
      assert.equals(1, vim.fn.filereadable(file))
      assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
    end)
  end)

  describe("watch mode (=l)", function()
    local store = require("scratch-manager.store")
    local runner = require("scratch-manager.runner")

    it("adds =l to C# pads only", function()
      sm.setup({ enable_keymaps = false })
      edit_source("Program.cs")
      sm.toggle_scratch_pad()
      assert.equals("=l", calls[1].opts.win.keys.watch[1])
      sm.toggle_scratch_pad("markdown")
      assert.is_nil(calls[2].opts.win.keys.watch)
      sm.setup({ enable_keymaps = false, keymaps = { pad_watch = false } })
      sm.toggle_scratch_pad()
      assert.is_nil(calls[3].opts.win.keys.watch)
    end)

    it("remembers watch mode per pad and turns it back on when the pad opens again", function()
      -- a stand-in command, and no .Dump() so nothing actually runs
      sm.setup({ enable_keymaps = false, run = { cs = { cmd = { "true" } } } })
      local root = vim.fn.stdpath("data") .. "/scratch"
      assert.truthy(root:find(vim.env.SCRATCH_MANAGER_TEST_HOME, 1, true))
      vim.fn.mkdir(root, "p")
      local file = normalize(root .. "/watched.cs")
      vim.fn.writefile({ "var a = 1;" }, file)
      vim.cmd.edit(vim.fn.fnameescape(file))
      vim.bo.filetype = "cs"
      local buf = vim.api.nvim_get_current_buf()

      assert.is_true(sm.toggle_watch(buf))
      assert.is_true(store.get("pad_watch", file))
      assert.truthy(notifications[#notifications].msg:find("Watch on", 1, true))

      -- closed and opened again (new buffer): watch mode comes back
      vim.cmd("bwipeout! " .. buf)
      assert.is_false(runner.watching(buf))
      vim.cmd.edit(vim.fn.fnameescape(file))
      vim.bo.filetype = "cs"
      local again = vim.api.nvim_get_current_buf()
      assert.is_true(runner.watching(again))

      assert.is_false(sm.toggle_watch(again))
      assert.is_nil(store.get("pad_watch", file))
    end)

    it("says when a pad's language has no watch mode", function()
      sm.setup({ enable_keymaps = false })
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].filetype = "markdown"
      assert.is_false(sm.toggle_watch(buf))
      assert.truthy(notifications[#notifications].msg:find("isn't available", 1, true))
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

    it("also saves shortly after typing pauses in insert mode", function()
      sm.setup({ enable_keymaps = false })
      local file = edit_unsaved_pad()
      vim.cmd("doautocmd TextChangedI")
      assert.is_true(vim.bo.modified) -- not immediately
      vim.wait(1000, function()
        return not vim.bo.modified
      end)
      assert.is_false(vim.bo.modified)
      assert.same({ "Console.WriteLine(1);" }, vim.fn.readfile(file))
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

      it("stacks the badges down the right edge with layout = column, and keeps pads clear of them", function()
        vim.o.columns = 150
        local indicator = { float = true, icon = "N", code_icon = "C", db_icon = "D", layout = "column" }
        sm.setup({ enable_keymaps = false, indicator = indicator })
        list_items = { pad("bar.lua", "markdown"), pad("bar.lua", "lua"), pad("bar.lua", "sql") }
        edit_source("bar.lua")
        sm.refresh_indicator()
        local top = math.max(badge.tabline_height(), 1) -- level with the pads' top border
        local rows, cols = {}, {}
        for _, kind in ipairs({ "notes", "code", "db" }) do
          local cfg = vim.api.nvim_win_get_config(badge.get_win(kind))
          table.insert(rows, cfg.row)
          table.insert(cols, cfg.col)
        end
        assert.same({ top, top + 3, top + 6 }, rows) -- one under the other
        assert.same({ 150 - 1 - 5, 150 - 1 - 5, 150 - 1 - 5 }, cols) -- same right edge

        -- pads open left of the badges: icon + " 9" (3) + padding 2 + borders 2 + margin/gap 2 = 9
        sm.toggle_scratch_pad("lua")
        local win = calls[#calls].opts.win
        assert.equals(150 - 9 - win.width, win.col)

        -- a single badge (only one kind of pad): the pad takes the space
        list_items = { pad("bar.lua", "markdown") }
        sm.refresh_indicator()
        sm.toggle_scratch_pad("markdown")
        win = calls[#calls].opts.win
        assert.equals(150 - win.width, win.col)
        -- opening a second kind makes two badges: room is kept
        sm.toggle_scratch_pad("lua")
        win = calls[#calls].opts.win
        assert.equals(150 - 9 - win.width, win.col)

        -- the default row layout leaves pads where they were
        sm.setup({ enable_keymaps = false, indicator = { float = true } })
        sm.toggle_scratch_pad("lua")
        win = calls[#calls].opts.win
        assert.equals(150 - win.width, win.col)
      end)

      it("lines stacked badges up with the pad's top and joins the open pad to its badge", function()
        vim.wait(100) -- updates scheduled by earlier tests' plugin instances run first
        vim.o.columns = 150
        sm.setup({ enable_keymaps = false, indicator = { float = true, layout = "column", icon = "N" } })
        local md_pad = pad("bar.lua", "markdown")
        list_items = { md_pad }
        local source = edit_source("bar.lua")
        sm.refresh_indicator()
        assert.equals(math.max(badge.tabline_height(), 1), vim.api.nvim_win_get_config(badge.get_win("notes")).row)
        assert.is_nil(badge._connector.win)

        -- a pad window where the plugin puts it (col = columns - gutter - width)
        local root = vim.fn.stdpath("data") .. "/scratch"
        vim.fn.mkdir(root, "p")
        local buf = vim.fn.bufadd(root .. "/notes_pad.markdown")
        vim.fn.bufload(buf)
        vim.bo[buf].filetype = "markdown"
        vim.b[buf].scratch_manager_source = vim.api.nvim_buf_get_name(source)
        local width = 50
        local gutter = 9 -- "N" + " 9", padding, borders, margin/gap... (see the column layout test)
        local pad_win = vim.api.nvim_open_win(buf, true, {
          relative = "editor", row = 1, col = 150 - gutter - width, width = width, height = 20, border = "rounded",
        })
        sm.refresh_indicator()
        local conn = badge._connector.win
        assert.is_not_nil(conn)
        local cfg = vim.api.nvim_win_get_config(conn)
        local badge_cfg = vim.api.nvim_win_get_config(badge.get_win("notes"))
        assert.equals(badge_cfg.row + 1, cfg.row) -- the badge's middle row
        assert.equals(150 - gutter - width + width + 1, cfg.col) -- on the pad's right border
        local text = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(conn), 0, 1, false)[1]
        assert.truthy(text:match("^├─*┤$"))
        assert.equals(badge_cfg.col, cfg.col + vim.api.nvim_strwidth(text) - 1) -- ends on the badge's border

        -- updates move the connector instead of reopening it: closing it would fire WinClosed,
        -- which updates the badges again, in an endless loop (flicker, CPU)
        vim.api.nvim_exec_autocmds("WinClosed", { pattern = tostring(conn) })
        vim.wait(200)
        sm.refresh_indicator()
        vim.wait(200)
        assert.equals(conn, badge._connector.win)

        vim.api.nvim_win_close(pad_win, true)
        sm.refresh_indicator()
        assert.is_nil(badge._connector.win)
        -- and its own closing doesn't trigger another round
        local before = vim.fn.win_getid(vim.fn.winnr("$"))
        vim.wait(200)
        assert.is_nil(badge._connector.win)
        assert.equals(before, vim.fn.win_getid(vim.fn.winnr("$")))
      end)

      it("doesn't loop when badges close: their WinClosed starts no update", function()
        sm.setup({ enable_keymaps = false, indicator = { float = true, layout = "column" } })
        list_items = { pad("bar.lua", "markdown"), pad("bar.lua", "lua") }
        edit_source("bar.lua")
        sm.refresh_indicator()
        vim.wait(100) -- let updates already scheduled (BufEnter while setting up) run first
        local updates = 0
        local refresh = sm.refresh_indicator
        sm.refresh_indicator = function(...)
          updates = updates + 1
          return refresh(...)
        end
        vim.api.nvim_win_close(badge.get_win("code"), true) -- fires WinClosed for a badge
        vim.wait(200)
        sm.refresh_indicator = refresh
        assert.equals(0, updates)
      end)

      it("keeps stacked badges up inside a pad, showing its source file's pads", function()
        sm.setup({ enable_keymaps = false, indicator = { float = true, layout = "column" } })
        local md_pad = pad("bar.lua", "markdown")
        list_items = { md_pad }
        local source = edit_source("bar.lua")
        sm.refresh_indicator()
        local root = vim.fn.stdpath("data") .. "/scratch"
        vim.fn.mkdir(root, "p")
        vim.cmd.edit(vim.fn.fnameescape(root .. "/notes_pad.markdown"))
        vim.b.scratch_manager_source = vim.api.nvim_buf_get_name(source)
        sm.refresh_indicator()
        assert.is_not_nil(badge.get_win("notes"))

        -- the default layout hides them inside a pad, as before
        sm.setup({ enable_keymaps = false, indicator = { float = true } })
        sm.refresh_indicator()
        assert.is_nil(badge.get_win("notes"))
      end)

      it("uses the editor background like the pads, or the float background when not transparent", function()
        sm.setup({ enable_keymaps = false, indicator = { float = true } })
        list_items = { pad("bar.lua", "markdown") }
        edit_source("bar.lua")
        sm.refresh_indicator()
        local win = badge.get_win("notes")
        assert.truthy(vim.wo[win].winhighlight:find("NormalFloat:Normal,", 1, true))
        -- the icon keeps its color through an extmark
        local marks = vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(win), -1, 0, -1, { details = true })
        assert.equals("ScratchManagerBadge", marks[1][4].hl_group)

        sm.setup({ enable_keymaps = false, indicator = { float = true, transparent = false } })
        sm.refresh_indicator()
        assert.truthy(vim.wo[badge.get_win("notes")].winhighlight:find("NormalFloat:NormalFloat,", 1, true))
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

      it("keeps the dashboard header color after a colorscheme change (B13)", function()
        sm.setup({ enable_keymaps = false, dashboard_color = "#4ecdc4" })
        vim.cmd("highlight clear")
        vim.cmd("doautocmd ColorScheme")
        assert.equals("#4ecdc4", string.format("#%06x", vim.api.nvim_get_hl(0, { name = "SnacksDashboardHeader" }).fg))
      end)

      it("colors .Dump() values orange by default (not like diagnostics), configurable", function()
        sm.setup({ enable_keymaps = false })
        local default = vim.api.nvim_get_hl(0, { name = "ScratchManagerDump" })
        assert.is_nil(default.link)
        assert.equals("#fab387", string.format("#%06x", default.fg))
        sm.setup({ enable_keymaps = false, highlights = { dump = { fg = "#94e2d5", italic = true } } })
        local hl = vim.api.nvim_get_hl(0, { name = "ScratchManagerDump" })
        assert.equals("#94e2d5", string.format("#%06x", hl.fg))
        assert.is_true(hl.italic)
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
        assert.is_nil(calls[2].opts.win.keys.run)

        sm.setup({ enable_keymaps = false, run = { cs = { enabled = false } } })
        sm.toggle_scratch_pad()
        assert.is_nil(calls[3].opts.win.keys.run)
      end)
    end)

    it("does not register autocmds when disabled", function()
      sm.setup({ enable_keymaps = false, indicator = { enabled = false } })
      assert.equals(0, #vim.api.nvim_get_autocmds({ group = "ScratchManagerIndicator" }))
    end)
  end)
end)
