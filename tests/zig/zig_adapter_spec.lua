local ts = require("quicktest.adapters.zig.ts")
local cmd = require("quicktest.adapters.zig.cmd")
local adapter = require("quicktest.adapters.zig")

describe("Zig adapter", function()
  describe("TreeSitter queries", function()
    it("can extract test names from buffer", function()
      -- Create a buffer with Zig test code
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(bufnr, "filetype", "zig")

      local content = {
        'const std = @import("std");',
        "",
        'test "first test" {',
        "    try std.testing.expect(true);",
        "}",
        "",
        'test "second test" {',
        "    try std.testing.expect(true);",
        "}",
      }

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

      -- Parse the treesitter to ensure it's loaded
      vim.treesitter.get_parser(bufnr, "zig"):parse()

      local test_names = ts.get_test_names(bufnr)

      assert.are.equal(2, #test_names)
      assert.are.equal("first test", test_names[1])
      assert.are.equal("second test", test_names[2])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("can find current test name from cursor position", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(bufnr, "filetype", "zig")

      local content = {
        'const std = @import("std");',
        "",
        'test "my test" {',
        "    try std.testing.expect(true);",
        "}",
      }

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
      vim.treesitter.get_parser(bufnr, "zig"):parse()

      -- Cursor on line 3 (0-indexed line 2), column 0 (inside the test)
      local test_name = ts.get_current_test_name(bufnr, { 2, 0 })

      assert.are.equal("my test", test_name)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("can find test definition line number", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(bufnr, "filetype", "zig")

      local content = {
        'const std = @import("std");',
        "",
        'test "target test" {',
        "    try std.testing.expect(true);",
        "}",
      }

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
      vim.treesitter.get_parser(bufnr, "zig"):parse()

      local line_no = ts.get_test_def_line_no(bufnr, "target test")

      -- Line numbers are 0-indexed, so test starts at line 2
      assert.are.equal(2, line_no)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("Command building", function()
    it("builds basic test command without filters", function()
      local args = cmd.build_args({}, {}, "test-filter")

      assert.are.equal(4, #args)
      assert.are.equal("build", args[1])
      assert.are.equal("test", args[2])
      assert.are.equal("--summary", args[3])
      assert.are.equal("all", args[4])
    end)

    it("builds test command with filter", function()
      local args = cmd.build_args({ "my test" }, {}, "test-filter")

      assert.are.equal(5, #args)
      assert.are.equal("build", args[1])
      assert.are.equal("test", args[2])
      assert.are.equal("--summary", args[3])
      assert.are.equal("all", args[4])
      assert.are.equal('-Dtest-filter=my test', args[5])
    end)

    it("builds test command with multiple filters", function()
      local args = cmd.build_args({ "first test", "second test" }, {}, "test-filter")

      assert.are.equal(6, #args)
      assert.are.equal("build", args[1])
      assert.are.equal("test", args[2])
      assert.are.equal("--summary", args[3])
      assert.are.equal("all", args[4])
      assert.are.equal('-Dtest-filter=first test', args[5])
      assert.are.equal('-Dtest-filter=second test', args[6])
    end)

    it("builds test command with custom filter option name", function()
      local args = cmd.build_args({ "my test" }, {}, "custom-filter")

      assert.are.equal('-Dcustom-filter=my test', args[5])
    end)

    it("builds test command with additional args", function()
      local args = cmd.build_args({ "my test" }, { "--verbose", "--debug" }, "test-filter")

      assert.are.equal(7, #args)
      assert.are.equal("--verbose", args[6])
      assert.are.equal("--debug", args[7])
    end)
  end)

  describe("Adapter configuration", function()
    it("has correct name", function()
      assert.are.equal("zig", adapter.name)
    end)

    it("is enabled for .zig files", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "test.zig")

      local enabled = adapter.is_enabled(bufnr, "file")

      assert.is_true(enabled)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("is not enabled for non-.zig files", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, "test.go")

      local enabled = adapter.is_enabled(bufnr, "file")

      assert.is_false(enabled)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
