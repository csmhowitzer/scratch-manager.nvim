-- Language servers in pads through clean mirror files (idea #10)

package.loaded["snacks"] = {
  scratch = setmetatable({
    open = function() end,
    list = function()
      return {}
    end,
  }, { __call = function() end }),
  util = {
    icon = function()
      return "x"
    end,
    file_decode = function(s)
      return (s:gsub("_%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
      end))
    end,
  },
}

describe("scratch-manager.lsp (servers in pads)", function()
  local sm = require("scratch-manager")
  local pad_lsp = require("scratch-manager.lsp")
  local tmp, root

  -- A pad buffer with a snacks-style encoded name under the scratch root
  local function pad_buf(ft, name)
    local file = root .. "/1_%7C_%7CScratch Pad _%28" .. name .. "_%29_%7C_%2Ftmp_%7Cmain." .. ft
    vim.cmd.edit(vim.fn.fnameescape(file))
    vim.bo.filetype = ft
    return vim.api.nvim_get_current_buf()
  end

  -- In-process server that records the notifications it receives
  local function fake_server(name, bufnr)
    local received = {}
    local id = vim.lsp.start({
      name = name,
      cmd = function()
        return {
          request = function(method, _, callback)
            callback(nil, method == "initialize" and { capabilities = { textDocumentSync = 1 } } or nil)
            return true, 1
          end,
          notify = function(method, params)
            table.insert(received, { method = method, uri = params and params.textDocument and params.textDocument.uri })
            return true
          end,
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
    vim.wait(100)
    return id, received
  end

  before_each(function()
    tmp = vim.fn.tempname()
    root = vim.fn.stdpath("data") .. "/scratch"
    vim.fn.mkdir(root, "p")
    sm.setup({ enable_keymaps = false })
  end)

  after_each(function()
    vim.cmd("silent! %bwipeout!")
  end)

  it("names mirror files after the pad, in a per-pad directory", function()
    local path = pad_lsp.mirror_path("/x/pad.cs", "StringExtensions.cs", "cs")
    assert.truthy(path:find("/scratch%-manager/lsp/%x+/StringExtensionsPad%.cs$"))
    assert.are_not.equal(path, pad_lsp.mirror_path("/y/pad.cs", "StringExtensions.cs", "cs"))
    assert.truthy(pad_lsp.mirror_path("/x/pad.cs", nil, "cs"):find("/ScratchPad%.cs$"))
  end)

  it("lets Roslyn into C# pads under a clean mirror URI, and nothing under the encoded name", function()
    local pad = pad_buf("cs", "StringExtensions.cs")
    local id, received = fake_server("roslyn", pad)
    assert.is_true(vim.lsp.buf_is_attached(pad, id))

    local mirror = pad_lsp.mirror(pad)
    assert.truthy(mirror:find("StringExtensionsPad%.cs$"))
    local uris = {}
    for _, n in ipairs(received) do
      if n.uri then
        table.insert(uris, n.uri)
      end
    end
    assert.truthy(#uris > 0)
    for _, uri in ipairs(uris) do
      assert.equals(vim.uri_from_fname(mirror), uri)
      assert.is_nil(uri:find("%%25", 1)) -- no double-encoded snacks name
    end
    -- replies addressed to the mirror land in the pad
    assert.equals(pad, vim.uri_to_bufnr(vim.uri_from_fname(mirror)))
  end)

  it("keeps other servers off pads, and languages without lsp support unmirrored", function()
    local pad = pad_buf("cs", "A.cs")
    local other = fake_server("some_other_server", pad)
    assert.is_false(vim.lsp.buf_is_attached(pad, other))

    local notes = pad_buf("markdown", "A.cs")
    local marksman = fake_server("marksman", notes)
    assert.is_false(vim.lsp.buf_is_attached(notes, marksman))
    assert.is_nil(pad_lsp.mirror(notes))
  end)

  it("can be turned off with lsp.mirror = false", function()
    sm.setup({ enable_keymaps = false, lsp = { mirror = false } })
    local pad = pad_buf("cs", "B.cs")
    local id = fake_server("roslyn", pad)
    assert.is_false(vim.lsp.buf_is_attached(pad, id))
    assert.is_nil(pad_lsp.mirror(pad))
  end)

  it("adds the project reference to a mirrored C# pad, once", function()
    vim.fn.mkdir(tmp .. "/src/Billing", "p")
    vim.fn.writefile({ "<Project />" }, tmp .. "/src/Billing/Billing.csproj")
    local pad = pad_buf("cs", "Invoice.cs")
    vim.b[pad].scratch_manager_source = tmp .. "/src/Billing/Invoice.cs"
    vim.api.nvim_buf_set_lines(pad, 0, -1, false, { "var a = 1;" })
    fake_server("roslyn", pad)
    local lines = vim.api.nvim_buf_get_lines(pad, 0, -1, false)
    assert.same({ "#:project " .. tmp .. "/src/Billing/Billing.csproj", "var a = 1;" }, lines)

    require("scratch-manager.languages").get("cs").prepare_pad(pad, {})
    assert.equals(2, #vim.api.nvim_buf_get_lines(pad, 0, -1, false))
    -- and the mirror file has the same text
    assert.same(vim.api.nvim_buf_get_lines(pad, 0, -1, false), vim.fn.readfile(pad_lsp.mirror(pad)))
  end)

  it("hides .Dump() diagnostics in pads, but keeps real errors", function()
    local pad = pad_buf("cs", "C.cs")
    local id = fake_server("roslyn", pad)
    local client = vim.lsp.get_client_by_id(id)
    local uri = vim.uri_from_fname(pad_lsp.mirror(pad))
    client.handlers["textDocument/publishDiagnostics"](nil, {
      uri = uri,
      diagnostics = {
        { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 4 } }, severity = 1,
          message = "'string' does not contain a definition for 'Dump'" },
        { range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 4 } }, severity = 1,
          message = "Cannot implicitly convert type 'string' to 'int'" },
      },
    }, { client_id = id, method = "textDocument/publishDiagnostics" }, {})
    local diags = vim.diagnostic.get(pad)
    assert.equals(1, #diags)
    assert.truthy(diags[1].message:find("convert"))
  end)

  it("hides errors on .Dump() even when the project has its own Dump extension", function()
    local pad = pad_buf("cs", "F.cs")
    local id = fake_server("roslyn", pad)
    vim.api.nvim_buf_set_lines(pad, 0, -1, false, { 'ToPhone("x").Dump();', 'int bad = "oops";' })
    local client = vim.lsp.get_client_by_id(id)
    local uri = vim.uri_from_fname(pad_lsp.mirror(pad))
    client.handlers["textDocument/publishDiagnostics"](nil, {
      uri = uri,
      diagnostics = {
        -- Roslyn binds to the project's DictionaryExtensions.Dump<TKey, TValue> and flags the name
        { range = { start = { line = 0, character = 13 }, ["end"] = { line = 0, character = 17 } }, severity = 1, code = "CS0411",
          message = "The type arguments for method 'DictionaryExtensions.Dump<TKey, TValue>(Dictionary<TKey, TValue>)' cannot be inferred" },
        { range = { start = { line = 1, character = 10 }, ["end"] = { line = 1, character = 16 } }, severity = 1, code = "CS0029",
          message = "Cannot implicitly convert type 'string' to 'int'" },
      },
    }, { client_id = id, method = "textDocument/publishDiagnostics" }, {})
    assert.same({ "CS0029" }, vim.tbl_map(function(d) return d.code end, vim.diagnostic.get(pad)))
  end)

  it("puts pulled diagnostics (how Roslyn reports them) on the pad, not on a hidden mirror buffer", function()
    local pad = pad_buf("cs", "E.cs")
    local id = fake_server("roslyn", pad)
    local client = vim.lsp.get_client_by_id(id)
    local mirror = pad_lsp.mirror(pad)
    local uri = vim.uri_from_fname(mirror)
    local diag = function(line, message)
      return { range = { start = { line = line, character = 0 }, ["end"] = { line = line, character = 3 } }, severity = 1, message = message }
    end
    local ctx = { client_id = id, method = "textDocument/diagnostic", params = { textDocument = { uri = uri } } }
    client.handlers["textDocument/diagnostic"](nil, { kind = "full", items = { diag(0, "real error"), diag(1, "no definition for 'Dump'") } }, ctx, {})
    assert.same({ "real error" }, vim.tbl_map(function(d) return d.message end, vim.diagnostic.get(pad)))
    assert.equals(0, vim.fn.bufexists(mirror))

    -- "unchanged" keeps what's there
    client.handlers["textDocument/diagnostic"](nil, { kind = "unchanged", resultId = "1" }, ctx, {})
    assert.equals(1, #vim.diagnostic.get(pad))
  end)

  it("hides 'unnecessary using' in pads (=p brings all of a file's usings)", function()
    local pad = pad_buf("cs", "G.cs")
    local id = fake_server("roslyn", pad)
    vim.api.nvim_buf_set_lines(pad, 0, -1, false, { "using System.Text;", "using System.Globalization;", "var a = 1;" })
    local client = vim.lsp.get_client_by_id(id)
    client.handlers["textDocument/publishDiagnostics"](nil, {
      uri = vim.uri_from_fname(pad_lsp.mirror(pad)),
      diagnostics = {
        { range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 27 } }, severity = 4, code = "IDE0005",
          message = "Using directive is unnecessary.", tags = { 1 } },
        { range = { start = { line = 2, character = 4 }, ["end"] = { line = 2, character = 5 } }, severity = 2, code = "CS0219",
          message = "The variable 'a' is assigned but its value is never used" },
      },
    }, { client_id = id, method = "textDocument/publishDiagnostics" }, {})
    assert.same({ "CS0219" }, vim.tbl_map(function(d) return d.code end, vim.diagnostic.get(pad)))
  end)

  it("shortens the #:project path on screen, keeping the full path in the text", function()
    local cs = require("scratch-manager.languages").get("cs")
    local buf = vim.api.nvim_create_buf(false, true)
    local line = "#:project /mnt/c/projects/App Connections/Core/AccuLynx.Core.csproj"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line, "var a = 1;" })
    cs.decorate(buf)
    local marks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
    local conceal = vim.tbl_filter(function(m) return m[4].conceal end, marks)[1]
    assert.equals("…", conceal[4].conceal)
    assert.equals("/mnt/c/projects/App Connections/Core/", line:sub(conceal[3] + 1, conceal[4].end_col))
    -- the whole directive line is shown as a comment, above semantic token colors (125)
    local comment = vim.tbl_filter(function(m) return m[4].hl_group == "Comment" end, marks)
    assert.equals(1, #comment)
    assert.equals(0, comment[1][2])
    assert.equals(#line, comment[1][4].end_col)
    assert.is_true(comment[1][4].priority > 125)
    assert.equals(line, vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    assert.same({ conceallevel = 2, concealcursor = "" }, cs.wo)
  end)

  it("keeps Treesitter off #: lines so a parse error can't spread into the code", function()
    local cs = require("scratch-manager.languages").get("cs")
    assert.same({ { 1, 0, 2, 10 }, { 4, 0, 4, 3 } },
      cs.parse_ranges({ "#:project /x/A.csproj", "using X;", "var a = 1;", "#:package B@1", "x()" }))
    if not pcall(vim.treesitter.language.add, "c_sharp") then
      pending("c_sharp parser not installed")
      return
    end
    local buf = vim.api.nvim_create_buf(false, true)
    -- this exact text breaks the C# grammar from line 1 into the local function
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "#:project /mnt/c/x/App Connections/Core.csproj", "",
      "// from A.cs:1", "string ToPhone(string input)", "{", "    if (string.IsNullOrEmpty(input))", "        return input;",
      "    var p = new string(input.Where(c => char.IsDigit(c)).ToArray());", "    return p;", "}" })
    cs.update_parse_ranges(buf)
    local root = vim.treesitter.get_parser(buf, "c_sharp"):parse(true)[1]:root()
    assert.is_false(root:has_error())
  end)

  it("keeps the mirror file in sync when the pad saves", function()
    local pad = pad_buf("cs", "D.cs")
    fake_server("roslyn", pad)
    vim.api.nvim_buf_set_lines(pad, 0, -1, false, { "Console.WriteLine(2);" })
    vim.cmd("doautocmd TextChanged")
    assert.same({ "Console.WriteLine(2);" }, vim.fn.readfile(pad_lsp.mirror(pad)))
  end)
end)
