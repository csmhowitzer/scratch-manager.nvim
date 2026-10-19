-- Tests for DB (SQL) pads: provider resolution, connection memory, running

describe("scratch-manager.sql", function()
  local sql = require("scratch-manager.sql")
  local executed, original_select, original_notify, messages

  -- A provider that records what it was asked to run
  local function fake_provider(overrides)
    return vim.tbl_extend("force", {
      name = "fake",
      available = function()
        return true
      end,
      connections = function()
        return { { name = "Dev", type = "sqlserver" }, { name = "Local", type = "sqlite" } }
      end,
      execute = function(conn, query, bufnr)
        table.insert(executed, { conn = conn.name, query = query, bufnr = bufnr })
      end,
    }, overrides or {})
  end

  local function pad_buffer(lines)
    vim.cmd.edit(vim.fn.fnameescape(vim.fn.tempname() .. ".sql"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    return vim.api.nvim_get_current_buf()
  end

  -- Answer the next connection picker with the given name
  local function answer_picker(name)
    vim.ui.select = function(items, _, on_choice)
      for _, item in ipairs(items) do
        if item.name == name then
          return on_choice(item)
        end
      end
      on_choice(nil)
    end
  end

  before_each(function()
    executed, messages = {}, {}
    original_select, original_notify = vim.ui.select, vim.notify
    vim.notify = function(msg)
      table.insert(messages, msg)
    end
  end)

  after_each(function()
    vim.ui.select, vim.notify = original_select, original_notify
    vim.cmd("silent! %bwipeout!")
  end)

  it("never needs enhance.nvim: the built-in adapter reports unavailable when it is missing", function()
    local provider, err = sql.get_provider({ provider = "enhance" })
    assert.is_nil(provider)
    assert.truthy(err:find("not available"))
  end)

  it("can be disabled or given a custom provider", function()
    assert.is_nil((sql.get_provider({ provider = false })))
    assert.equals("fake", sql.get_provider({ provider = fake_provider() }).name)
    assert.is_nil((sql.get_provider({ provider = { name = "broken" } })))
  end)

  it("asks for a connection on the first run, then remembers it for the pad", function()
    local provider = fake_provider()
    local buf = pad_buffer({ "SELECT 1;" })
    answer_picker("Dev")
    sql.run(buf, { provider = provider })
    assert.same({ conn = "Dev", query = "SELECT 1;", bufnr = buf }, executed[1])

    vim.ui.select = function()
      error("should not ask again")
    end
    sql.run(buf, { provider = provider })
    assert.equals("Dev", executed[2].conn)
    assert.equals("Dev", sql.get_connection_name(vim.api.nvim_buf_get_name(buf)))
  end)

  it("switches the remembered connection", function()
    local provider = fake_provider()
    local buf = pad_buffer({ "SELECT 1;" })
    answer_picker("Local")
    sql.choose_connection(buf, { provider = provider })
    sql.run(buf, { provider = provider })
    assert.equals("Local", executed[1].conn)
  end)

  it("closes the pad window before running so results get the width (unless disabled)", function()
    local provider = fake_provider()
    answer_picker("Dev")
    vim.cmd("vsplit")
    local buf = pad_buffer({ "SELECT 1;" })
    local pad_win = vim.api.nvim_get_current_win()
    sql.run(buf, { provider = provider })
    assert.is_false(vim.api.nvim_win_is_valid(pad_win))

    vim.cmd("vsplit")
    local buf2 = pad_buffer({ "SELECT 2;" })
    local win2 = vim.api.nvim_get_current_win()
    sql.run(buf2, { provider = provider, close_pad = false })
    assert.is_true(vim.api.nvim_win_is_valid(win2))
  end)

  it("explains what to do when no provider is available", function()
    sql.run(pad_buffer({ "SELECT 1;" }), { provider = false })
    assert.equals(0, #executed)
    assert.truthy(messages[1]:find("run.sql.provider"))
  end)

  it("attaches the connection (completion) on the first pick and when switching", function()
    local attached = {}
    local provider = fake_provider({
      attach = function(conn, bufnr)
        table.insert(attached, { conn = conn.name, bufnr = bufnr })
      end,
    })
    local buf = pad_buffer({ "SELECT 1;" })
    answer_picker("Dev")
    sql.run(buf, { provider = provider })
    assert.same({ conn = "Dev", bufnr = buf }, attached[1])

    answer_picker("Local")
    sql.choose_connection(buf, { provider = provider })
    assert.equals("Local", attached[2].conn)
  end)

  it("attaches a remembered connection when the pad is opened, quietly otherwise", function()
    local attached = {}
    local provider = fake_provider({
      attach = function(conn)
        table.insert(attached, conn.name)
      end,
    })
    local buf = pad_buffer({ "SELECT 1;" })
    sql.attach_pad(buf, { provider = provider })
    assert.same({}, attached) -- nothing remembered yet: no prompt, no attach

    sql.set_connection_name(vim.api.nvim_buf_get_name(buf), "Local")
    sql.attach_pad(buf, { provider = provider })
    assert.same({ "Local" }, attached)
    assert.same({}, messages)
  end)

  it("works with providers that have no attach", function()
    local buf = pad_buffer({ "SELECT 1;" })
    answer_picker("Dev")
    assert.has_no.errors(function()
      sql.run(buf, { provider = fake_provider() })
    end)
    assert.equals(1, #executed)
  end)

  describe("enhance adapter", function()
    local adapter = require("scratch-manager.providers.enhance")
    local calls

    before_each(function()
      calls = {}
      package.loaded["enhance.api"] = {
        version = 1,
        connections = function()
          return { { name = "Dev", type = "sqlserver" } }
        end,
        execute = function(query, opts)
          table.insert(calls, { "execute", query, opts.connection.name, opts.bufnr })
          return true
        end,
        attach = function(bufnr, conn)
          table.insert(calls, { "attach", bufnr, conn.name })
          return true
        end,
      }
    end)

    after_each(function()
      package.loaded["enhance.api"] = nil
    end)

    it("uses enhance's public API when it exists", function()
      assert.is_true(adapter.available())
      assert.equals("Dev", adapter.connections()[1].name)
      adapter.execute({ name = "Dev" }, "SELECT 1", 5)
      adapter.attach({ name = "Dev" }, 5)
      assert.same({ { "execute", "SELECT 1", "Dev", 5 }, { "attach", 5, "Dev" } }, calls)
    end)

    it("falls back to enhance's completion setup when there is no public API", function()
      package.loaded["enhance.api"] = nil
      local setup_calls = {}
      package.loaded["enhance.completion"] = {
        setup = function(bufnr, conn)
          table.insert(setup_calls, { bufnr, conn.name })
        end,
      }
      adapter.attach({ name = "Dev" }, 9)
      package.loaded["enhance.completion"] = nil
      assert.same({ { 9, "Dev" } }, setup_calls)
    end)

    it("ignores a newer-but-incompatible or missing API", function()
      package.loaded["enhance.api"] = { version = 0 }
      assert.is_false(adapter.available()) -- and no enhance internals in the test env either
      assert.has_no.errors(function()
        adapter.attach({ name = "Dev" }, 5)
      end)
    end)
  end)

  it("does not run an empty pad", function()
    sql.run(pad_buffer({ "", "  " }), { provider = fake_provider() })
    assert.equals(0, #executed)
  end)

  it("enhance provider: fills vim-dadbod-completion's cache on attach, while the pad is on screen", function()
    local saved_api = package.loaded["enhance.api"]
    package.loaded["enhance.api"] = {
      version = 1,
      attach = function(bufnr)
        vim.b[bufnr].db = "sqlserver://example"
      end,
    }
    -- stand-in for vim-dadbod-completion (autoload functions can't be defined from a test)
    local fetched
    local exists = vim.fn.exists
    vim.fn.exists = function(name)
      return name == "*vim_dadbod_completion#fetch" and 1 or exists(name)
    end
    vim.fn["vim_dadbod_completion#fetch"] = function(b)
      fetched = b
    end
    local buf = vim.api.nvim_create_buf(false, true)
    package.loaded["scratch-manager.providers.enhance"] = nil
    require("scratch-manager.providers.enhance").attach({ name = "Dev" }, buf)
    vim.fn.exists = exists
    vim.fn["vim_dadbod_completion#fetch"] = nil
    assert.equals(buf, fetched)

    package.loaded["enhance.api"] = saved_api
    package.loaded["scratch-manager.providers.enhance"] = nil
  end)
end)
