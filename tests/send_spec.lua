-- Tests for sending code to a pad (=p) and the language profiles behind it

describe("scratch-manager.send", function()
  local send = require("scratch-manager.send")
  local languages = require("scratch-manager.languages")
  local cs = languages.get("cs")

  local function buffer(name, ft, lines)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "/" .. name)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = ft
    vim.api.nvim_set_current_buf(buf)
    return buf
  end

  after_each(function()
    vim.cmd("silent! %bwipeout!")
  end)

  describe("language profiles", function()
    it("give every filetype safe defaults", function()
      local plain = languages.get("python")
      assert.same({}, plain.imports({ "import os" }))
      assert.is_false(plain.is_import("import os"))
      assert.same({ "x" }, (plain.adapt({ "x" })))
      assert.equals(3, plain.insert_at({ "a", "b", "c" }))
    end)

    it("C#: collects using lines plus the file's namespace, once each", function()
      assert.same({ "using System.Text.Json;", "using static System.Math;", "using Billing;" }, cs.imports({
        "using System.Text.Json;",
        "global using Foo;",
        "using static System.Math;",
        "using System.Text.Json;",
        "",
        "namespace Billing;",
        "using var stream = Open();",
      }))
      assert.same({ "using Billing.Core;" }, cs.imports({ "namespace Billing.Core", "{" }))
    end)

    it("C#: turns a method into a local function, noting extension methods", function()
      local lines, note = cs.adapt({ "public static decimal Total(IEnumerable<LineItem> items)", "{", "}" }, "method_declaration")
      assert.same({ "decimal Total(IEnumerable<LineItem> items)", "{", "}" }, lines)
      assert.is_nil(note)

      lines, note = cs.adapt({ "public static string ToPhone(this string input)", "{" }, "method_declaration")
      assert.equals("string ToPhone(string input)", lines[1])
      assert.equals("was an extension method: call it as ToPhone(value, ...)", note)

      -- async stays, a plain selection without modifiers and non-method nodes are untouched
      assert.equals("async Task Run()", (cs.adapt({ "private async Task Run()" }, nil))[1])
      assert.same({ "var x = 1;" }, (cs.adapt({ "var x = 1;" }, nil)))
      assert.same({ "public Foo()" }, (cs.adapt({ "public Foo()" }, "constructor_declaration")))
    end)

    it("C#: inserts before top-level type declarations", function()
      assert.equals(2, cs.insert_at({ "var a = 1;", "", "record Order(string Id);" }))
      assert.equals(1, cs.insert_at({ "var a = 1;", "public sealed class Foo {}" }))
      assert.equals(2, cs.insert_at({ "var a = 1;", "    class Nested {}" }))
    end)
  end)

  it("removes common indentation", function()
    assert.same({ "if x then", "  y()", "", "end" }, send.dedent({ "    if x then", "      y()", "", "    end" }))
  end)

  it("finds the function under the cursor with Treesitter (Lua)", function()
    local buf = buffer("util.lua", "lua", { "local M = {}", "", "function M.add(a, b)", "  local c = a + b", "  return c", "end", "", "return M" })
    vim.treesitter.start(buf, "lua")
    vim.api.nvim_win_set_cursor(0, { 4, 4 })
    local range = send.target_range(buf, nil)
    assert.equals(3, range.first)
    assert.equals(6, range.last)
    -- outside a function: the current line; a selection wins
    vim.api.nvim_win_set_cursor(0, { 8, 0 })
    assert.same({ first = 8, last = 8 }, send.target_range(buf, nil))
    assert.same({ first = 1, last = 2 }, send.target_range(buf, { first = 1, last = 2 }))
  end)

  it("finds the C# method under the cursor (when the c_sharp parser is installed)", function()
    if not pcall(vim.treesitter.language.add, "c_sharp") then
      pending("c_sharp parser not installed")
      return
    end
    local buf = buffer("Calc.cs", "cs", {
      "namespace Billing;",
      "public static class Calc",
      "{",
      "    public static int Add(int a, int b)",
      "    {",
      "        return a + b;",
      "    }",
      "}",
    })
    vim.treesitter.start(buf, "c_sharp")
    vim.api.nvim_win_set_cursor(0, { 6, 10 })
    local range = send.target_range(buf, nil)
    assert.same({ first = 4, last = 7, node_type = "method_declaration" }, range)
  end)

  it("builds a commented block in the pad's language", function()
    local buf = buffer("util.lua", "lua", { "  local x = 1", "  print(x)" })
    local block, imports = send.build(buf, { first = 1, last = 2 }, "lua")
    assert.same({ "-- from util.lua:1–2", "local x = 1", "print(x)" }, block)
    assert.same({}, imports)

    local cbuf = buffer("Calc.cs", "cs", { "using System.Linq;", "namespace Billing;", "    public static int Add(int a, int b) => a + b;" })
    block, imports = send.build(cbuf, { first = 3, last = 3, node_type = "method_declaration" }, "cs")
    assert.same({ "// from Calc.cs:3", "int Add(int a, int b) => a + b;" }, block)
    assert.same({ "using System.Linq;", "using Billing;" }, imports)
  end)

  describe("insert", function()
    local function pad(lines)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      return buf
    end
    local function text(buf)
      return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    end

    it("fills an empty pad with the imports and the block", function()
      local buf = pad({ "" })
      local lnum, added = send.insert(buf, { "// from Calc.cs:3", "int Add() => 1;" }, { "using Billing;" }, "cs")
      assert.same({ "using Billing;", "", "// from Calc.cs:3", "int Add() => 1;" }, text(buf))
      assert.equals(3, lnum)
      assert.equals(1, added)
    end)

    it("adds only missing imports to the header and the block before types", function()
      local buf = pad({ "using System.Linq;", "", "var a = 1;", "", "record Order(string Id);" })
      local lnum, added = send.insert(buf, { "// from Calc.cs:3", "int Add() => 1;" }, { "using System.Linq;", "using Billing;" }, "cs")
      assert.same({
        "using System.Linq;", "using Billing;", "", "var a = 1;", "", "// from Calc.cs:3", "int Add() => 1;", "", "record Order(string Id);",
      }, text(buf)) -- System first, then the rest
      assert.equals(6, lnum)
      assert.equals(1, added)
    end)

    it("adds only missing imports on later sends and keeps C# usings sorted", function()
      local buf = pad({ "#:package Humanizer@2.14.1", "using Zeta.Tools;", "using System.Text;", "", "var a = 1;" })
      local _, added = send.insert(buf, { "// from B.cs:1", "int B() => 2;" },
        { "using System.Text;", "using Billing;", "using static System.Math;", "using System;", "using J = Newtonsoft.Json;" }, "cs")
      assert.equals(4, added)
      assert.same({
        "#:package Humanizer@2.14.1",
        "using System;",
        "using System.Text;",
        "using Billing;",
        "using Zeta.Tools;",
        "using static System.Math;",
        "using J = Newtonsoft.Json;",
        "",
        "var a = 1;",
        "",
        "// from B.cs:1",
        "int B() => 2;",
      }, text(buf))

      -- sending again from the same file adds no imports
      local _, again = send.insert(buf, { "// from B.cs:2", "int C() => 3;" }, { "using Billing;", "using System;" }, "cs")
      assert.equals(0, again)
    end)

    it("sorts the imports of an empty pad too", function()
      local buf = pad({ "" })
      send.insert(buf, { "// x" }, { "using Billing;", "using System.Linq;" }, "cs")
      assert.same({ "using System.Linq;", "using Billing;", "", "// x" }, text(buf))
    end)

    it("appends at the end for languages without a profile", function()
      local buf = pad({ "print('a')" })
      local lnum = send.insert(buf, { "# from x.py:1", "print('b')" }, {}, "python")
      assert.same({ "print('a')", "", "# from x.py:1", "print('b')" }, text(buf))
      assert.equals(3, lnum)
    end)
  end)
end)
