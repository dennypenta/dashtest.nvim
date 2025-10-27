local ts = require("quicktest.adapters.zig.ts")
local cmd = require("quicktest.adapters.zig.cmd")
local fs = require("quicktest.fs_utils")
local Job = require("plenary.job")

---@class ZigAdapterOptions
---@field cwd (fun(bufnr: integer, current: string?): string)?
---@field bin (fun(bufnr: integer, current: string?): string)?
---@field additional_args (fun(bufnr: integer): string[])?
---@field args (fun(bufnr: integer, current: string[]): string[])?
---@field env (fun(bufnr: integer, current: table<string, string>): table<string, string>)?
---@field is_enabled (fun(bufnr: integer, type: RunType, current: boolean): boolean)?
---@field test_filter_option (fun(bufnr: integer, current: string): string)?
---@field dap (fun(bufnr: integer, params: ZigRunParams): table)?

local M = {
  name = "zig",
  ---@type ZigAdapterOptions
  options = {},
}

local default_dap_opt = function(bufnr, params)
  return {
    showLog = true,
    logLevel = "debug",
  }
end

local ns = vim.api.nvim_create_namespace("quicktest-zig")

--- Strip ANSI color codes from a string
--- @param str string
--- @return string
local function strip_ansi_codes(str)
  -- Remove ANSI escape sequences more comprehensively
  -- ESC[ followed by any number of parameters and a final character
  local cleaned = str:gsub("\27%[[%d;]*%a", "")
  -- Also remove ESC followed by other sequences
  cleaned = cleaned:gsub("\27%]%d+;[^\7]*\7", "") -- OSC sequences
  cleaned = cleaned:gsub("\27%[[%d;]*", "") -- Incomplete sequences
  return cleaned
end

--- @param bufnr integer
--- @return string | nil
local function find_cwd(bufnr)
  local buffer_name = vim.api.nvim_buf_get_name(bufnr)
  local path = vim.fn.fnamemodify(buffer_name, ":p:h")

  return fs.find_ancestor_of_file(path, "build.zig")
end

-- Find the file containing a specific test function
---@param test_name string
---@param cwd string
---@return string?, integer?
local function find_test_location(test_name, cwd)
  -- Find all .zig files in the project
  local test_files = vim.fn.glob(cwd .. "/**/*.zig", false, true)

  for _, file_path in ipairs(test_files) do
    -- Check if file exists and is readable
    if vim.fn.filereadable(file_path) == 1 then
      -- Create a temporary buffer to search in
      local temp_bufnr = vim.fn.bufadd(file_path)
      vim.fn.bufload(temp_bufnr)

      -- Try to find the test in this file
      local line_no = ts.get_test_def_line_no(temp_bufnr, test_name)
      if line_no then
        return file_path, line_no + 1 -- Convert from 0-based to 1-based
      end
    end
  end

  return nil, nil
end

---@class ZigRunParams
---@field test_names string[]
---@field cwd string
---@field bufnr integer
---@field cursor_pos integer[]
---@field opts AdapterRunOpts

---@class ZigOutputState
---@field current_failing_test string?
---@field current_error_message string?
---@field test_results table<string, string>

---@param bufnr integer
---@return string
M.get_cwd = function(bufnr)
  local current = find_cwd(bufnr) or vim.fn.getcwd()

  return M.options.cwd and M.options.cwd(bufnr, current) or current
end

M.get_bin = function(bufnr)
  local current = "zig"

  return M.options.bin and M.options.bin(bufnr, current) or current
end

M.get_test_filter_option = function(bufnr)
  local current = "test-filter"

  return M.options.test_filter_option and M.options.test_filter_option(bufnr, current) or current
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return ZigRunParams | nil, string | nil
M.build_file_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)

  local test_names = ts.get_test_names(bufnr)
  if not test_names or #test_names == 0 then
    return nil, "No tests to run"
  end

  return {
    test_names = test_names,
    cwd = cwd,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    opts = opts,
  },
    nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return ZigRunParams | nil, string | nil
M.build_line_run_params = function(bufnr, cursor_pos, opts)
  local test_names = ts.get_nearest_test_names(bufnr, cursor_pos)

  local cwd = M.get_cwd(bufnr)

  if not test_names or #test_names == 0 then
    return nil, "No tests to run"
  end

  return {
    test_names = test_names,
    cwd = cwd,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    opts = opts,
  },
    nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return ZigRunParams | nil, string | nil
M.build_all_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)

  return {
    test_names = {},
    cwd = cwd,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    opts = opts,
  }, nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return ZigRunParams | nil, string | nil
M.build_dir_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)

  -- Collect all test names from the current buffer
  local test_names = ts.get_test_names(bufnr)

  return {
    test_names = test_names,
    cwd = cwd,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    opts = opts,
  },
    nil
end

---@param params ZigRunParams
---@return string[]
M.build_cmd = function(params)
  local additional_args = M.options.additional_args and M.options.additional_args(params.bufnr) or {}
  additional_args = params.opts.additional_args and vim.list_extend(additional_args, params.opts.additional_args)
    or additional_args

  local test_filter_option = M.get_test_filter_option(params.bufnr)

  local args = cmd.build_args(params.opts.cmd_override, params.test_names, additional_args, test_filter_option)
  args = M.options.args and M.options.args(params.bufnr, args) or args
  return args
end

---Parse a single line of Zig test plain text output and send structured events
---@param line string
---@param send fun(data: CmdData)
---@param params ZigRunParams
---@param state ZigOutputState
M.handle_output = function(line, send, params, state)
  -- Strip ANSI color codes for reliable parsing (especially in DAP mode)
  local clean_line = strip_ansi_codes(line)

  -- Parse test failures
  -- Format: 2/3 server_test.test.11...FAIL (Jo)
  -- Note: Line may end with \r (carriage return)
  local full_test_name, error_msg = clean_line:match("^%d+/%d+ (.-)%.%.%.FAIL %((.+)%)%s*$")

  if full_test_name then
    -- Extract just the test name (remove the module prefix)
    -- Format is typically: "module.test.test_name" or "test.test.test_name"
    local test_name = full_test_name:match("%.test%.(.+)$") or full_test_name
    state.current_failing_test = test_name
    state.current_error_message = error_msg

    -- Initialize test_results if it doesn't exist (e.g., when called from DAP)
    if not state.test_results then
      state.test_results = {}
    end

    -- Only mark test as failed if we haven't already
    if state.test_results[test_name] ~= "failed" then
      -- Send test_started first if we haven't seen this test before
      if not state.test_results[test_name] then
        send({
          type = "test_started",
          test_name = test_name,
          status = "running",
        })
      end
      -- Don't send test_result yet - wait for stack trace to get location
      state.test_results[test_name] = "failed"
    end
    return
  end

  -- Parse test location from stack trace
  -- Format: /path/to/test.zig:15:5: 0x100b5c857 in test.failed test (test)
  -- This line comes after the FAIL line, so we use current_failing_test
  -- We match the line that contains the exact test name
  if state.current_failing_test then
    -- Only process lines that start with a path (stack trace lines)
    if clean_line:match("^/") then
      -- Escape special pattern characters in test name for matching
      local escaped_test_name = state.current_failing_test:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
      -- Match line that contains "in test.<exact_test_name>"
      local pattern = "^([^:]+%.zig):(%d+):%d+:.* in test%." .. escaped_test_name .. " %("
      local file_path, line_str = clean_line:match(pattern)
      if file_path and line_str then
        local line_no = tonumber(line_str)

        -- Send assert_failure event for quickfix list
        send({
          type = "assert_failure",
          test_name = state.current_failing_test,
          full_path = file_path,
          line = line_no,
          message = state.current_error_message or "",
        })

        -- Also send test_result with location
        local location = file_path .. ":" .. line_str
        send({
          type = "test_result",
          test_name = state.current_failing_test,
          status = "failed",
          location = location,
        })

        -- Mark that we've sent the test_result
        if state.test_results then
          state.test_results[state.current_failing_test .. "_result_sent"] = true
        end

        state.current_failing_test = nil -- Reset after finding location
        state.current_error_message = nil
      end
    end
  end
end

---@param params ZigRunParams
---@param send fun(data: CmdData)
---@return integer
M.run = function(params, send)
  local args = M.build_cmd(params)

  local bin = M.get_bin(params.bufnr)

  local env = vim.fn.environ()
  env = M.options.env and M.options.env(params.bufnr, env) or env

  -- State for tracking running tests
  local state = { current_failing_test = nil, current_error_message = nil, test_results = {} }
  local all_output = {}

  -- Helper function to parse test failures from output
  local function process_output(data)
    table.insert(all_output, data)

    -- Parse output line by line using handle_output
    local lines = vim.split(data, "\n", { plain = true })
    for _, line in ipairs(lines) do
      if line ~= "" then
        M.handle_output(line, send, params, state)
      end
    end

    -- Always send as "stdout" so the colorizer can parse ANSI codes properly
    -- The UI treats "stderr" as errors and highlights everything in red,
    -- stripping ANSI codes. By sending as "stdout", we get proper color parsing.
    send({ type = "stdout", raw = data, output = data })
  end

  -- Emit test_started events for all tests we're about to run
  -- This ensures they exist in storage before we send test_result events
  if #params.test_names > 0 then
    for _, test_name in ipairs(params.test_names) do
      -- Find test location using treesitter
      local location = nil
      if params.bufnr and vim.api.nvim_buf_is_valid(params.bufnr) then
        local line_no = ts.get_test_def_line_no(params.bufnr, test_name)
        if line_no then
          local file_path = vim.api.nvim_buf_get_name(params.bufnr)
          location = file_path .. ":" .. (line_no + 1) -- Convert from 0-based to 1-based
        end
      end

      send({
        type = "test_started",
        test_name = test_name,
        status = "running",
        location = location,
      })
      state.test_results[test_name] = "running"
    end
  end

  local job = Job:new({
    command = bin,
    args = args,
    env = env,
    cwd = params.cwd,
    on_stdout = function(_, data)
      process_output(data)
    end,
    on_stderr = function(_, data)
      -- Zig sends ALL output to stderr, including test results
      -- But we treat it as stdout for proper color rendering
      process_output(data)
    end,
    on_exit = function(_, return_val)
      vim.schedule(function()
        -- Parse the test summary to emit test stats
        local output_text = table.concat(all_output, "\n")
        -- Strip ANSI codes for reliable parsing
        local clean_output = strip_ansi_codes(output_text)

        -- Extract test counts
        -- Format: "1 passed; 0 skipped; 2 failed."
        local passed_tests, skipped_tests, failed_tests = clean_output:match("(%d+) passed; (%d+) skipped; (%d+) failed%.")
        local total_tests = nil

        if passed_tests then
          -- Calculate total from passed + skipped + failed
          passed_tests = tonumber(passed_tests)
          skipped_tests = tonumber(skipped_tests)
          failed_tests = tonumber(failed_tests)
          total_tests = passed_tests + skipped_tests + failed_tests
        else
          -- Try success format: "All 3 tests passed."
          total_tests = clean_output:match("All (%d+) tests passed%.")
          if total_tests then
            passed_tests = tonumber(total_tests)
            failed_tests = 0
          end
        end

        if passed_tests and total_tests then
          passed_tests = tonumber(passed_tests)
          total_tests = tonumber(total_tests)
          failed_tests = tonumber(failed_tests)

          -- If we're running specific tests, finalize their status
          if #params.test_names > 0 then
            for _, test_name in ipairs(params.test_names) do
              local status = state.test_results[test_name]

              -- For tests still "running", mark as passed
              if status == "running" then
                -- Find test location using treesitter
                local location = nil
                if params.bufnr and vim.api.nvim_buf_is_valid(params.bufnr) then
                  local line_no = ts.get_test_def_line_no(params.bufnr, test_name)
                  if line_no then
                    local file_path = vim.api.nvim_buf_get_name(params.bufnr)
                    location = file_path .. ":" .. (line_no + 1) -- Convert from 0-based to 1-based
                  end
                end

                send({
                  type = "test_result",
                  test_name = test_name,
                  status = "passed",
                  location = location,
                })
                state.test_results[test_name] = "passed"
              -- For tests marked as "failed" but location not yet sent, send without location
              elseif status == "failed" and not state.test_results[test_name .. "_result_sent"] then
                send({
                  type = "test_result",
                  test_name = test_name,
                  status = "failed",
                })
                state.test_results[test_name .. "_result_sent"] = true
              end
            end
          else
            -- For run_all without specific test names, create generic test entries
            -- First send test_started, then test_result for passed tests
            local passed_count = passed_tests
            for i = 1, passed_count do
              local generic_name = "test_" .. i
              if not state.test_results[generic_name] then
                -- Send test_started first
                send({
                  type = "test_started",
                  test_name = generic_name,
                  status = "running",
                })
                -- Then send test_result
                send({
                  type = "test_result",
                  test_name = generic_name,
                  status = "passed",
                })
                state.test_results[generic_name] = "passed"
              end
            end
          end
        end

        send({ type = "exit", code = return_val })
      end)
    end,
  })
  job:start()

  ---@type integer
  ---@diagnostic disable-next-line: assign-type-mismatch
  local pid = job.pid

  return pid
end

M.title = function(params)
  local args = M.build_cmd(params)

  return "Running test: " .. table.concat(args, " ")
end

---@param params ZigRunParams
---@param results CmdData[]
M.after_run = function(params, results)
  local diagnostics = {}
  local storage = require("quicktest.storage")

  -- Collect all output for parsing
  local full_output = {}
  for _, result in ipairs(results) do
    if result.type == "stdout" or result.type == "stderr" then
      table.insert(full_output, result.output)
    end
  end

  local output_text = table.concat(full_output, "\n")
  -- Strip ANSI codes for reliable parsing
  local clean_output = strip_ansi_codes(output_text)

  -- Parse Zig test output to find failed tests
  local failed_tests = {}
  local current_failing_test = nil

  for line in clean_output:gmatch("[^\r\n]+") do
    -- Check if this is a test failure line
    -- Format: 2/3 server_test.test.11...FAIL (Jo)
    -- Note: Line may end with \r (carriage return)
    local full_test_name = line:match("^%d+/%d+ (.-)%.%.%.FAIL %((.+)%)%s*$")
    if full_test_name then
      -- Extract just the test name (remove the module prefix)
      -- Format is typically: "module.test.test_name" or "test.test.test_name"
      current_failing_test = full_test_name:match("%.test%.(.+)$") or full_test_name
    end

    -- Then, look for stack trace lines that match the test
    -- Stack trace format: /path/to/test.zig:15:5: 0x100d58857 in test.failed test (test)
    if current_failing_test and line:match("^/") then
      -- Escape special pattern characters in test name for matching
      local escaped_test_name = current_failing_test:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
      -- Match line that contains "in test.<exact_test_name>"
      local pattern = "^([^:]+%.zig):(%d+):%d+:.* in test%." .. escaped_test_name .. " %("
      local file_path, line_str = line:match(pattern)

      if file_path and line_str then
        local line_no = tonumber(line_str)

        table.insert(failed_tests, {
          test_name = current_failing_test,
          file_path = file_path,
          line = line_no,
        })

        -- Update storage with failure location
        storage.test_finished(current_failing_test, "failed", nil, file_path .. ":" .. line_no)

        current_failing_test = nil -- Reset after finding location
      end
    end
  end

  -- Add diagnostics for failed tests in the current buffer
  for _, failed in ipairs(failed_tests) do
    -- Try to find the test in the current buffer
    local line_no = ts.get_test_def_line_no(params.bufnr, failed.test_name)

    if line_no then
      table.insert(diagnostics, {
        lnum = line_no,
        col = 0,
        severity = vim.diagnostic.severity.ERROR,
        message = "FAILED",
        source = "Test",
        user_data = "test",
      })
    end
  end

  vim.diagnostic.set(ns, params.bufnr, diagnostics, {})
end

---@param bufnr integer
---@param type RunType
---@return boolean
M.is_enabled = function(bufnr, type)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local is_zig_file = vim.endswith(bufname, ".zig")

  if M.options.is_enabled == nil then
    return is_zig_file
  end

  return M.options.is_enabled(bufnr, type, is_zig_file)
end

---@param test_name string
---@param params ZigRunParams
---@return string?
M.find_test_location = function(test_name, params)
  local file_path, line_no = find_test_location(test_name, params.cwd)
  if file_path and line_no then
    return file_path .. ":" .. line_no
  end
  return nil
end

---@param bufnr integer
---@param params ZigRunParams
---@return table?
M.build_dap_config = function(bufnr, params)
  local additional_args = M.options.additional_args and M.options.additional_args(bufnr) or {}
  additional_args = params.opts.additional_args and vim.list_extend(additional_args, params.opts.additional_args)
    or additional_args

  local env = vim.fn.environ()
  env = M.options.env and M.options.env(bufnr, env) or env

  -- For Zig, we need to use the LLDB adapter
  local config = {
    type = "codelldb",
    name = "Debug Zig Test",
    request = "launch",
    program = function()
      -- The test executable is built in .zig-cache
      -- We need to run zig build test first to generate it
      -- For now, we'll just return a placeholder - users may need to customize this
      return vim.fn.getcwd() .. "/zig-out/bin/test"
    end,
    env = env,
    cwd = params.cwd,
    stopOnEntry = false,
  }

  if M.options.dap then
    config = vim.tbl_extend("force", config, M.options.dap(bufnr, params))
  end

  return config
end

--- Adapter options.
setmetatable(M, {
  ---@param opts ZigAdapterOptions
  __call = function(_, opts)
    opts = opts or {}
    if opts.dap == nil then
      opts.dap = default_dap_opt
    end
    M.options = opts

    return M
  end,
})

return M
