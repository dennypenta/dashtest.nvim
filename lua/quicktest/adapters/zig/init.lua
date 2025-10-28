local ts = require("quicktest.adapters.zig.ts")
local cmd = require("quicktest.adapters.zig.cmd")
local fs = require("quicktest.fs_utils")
local Job = require("plenary.job")
local adapter_args = require("quicktest.adapters.args")

local M = {
  name = "zig",
  ---@type AdapterOptions
  options = {},
}

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
---@field output_state OutputState

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
  local additional_args = adapter_args.merge_additional_args(M.options, params.bufnr, params.opts)
  local test_filter_option = M.get_test_filter_option(params.bufnr)
  local args = cmd.build_args(params.opts.cmd_override, params.test_names, additional_args, test_filter_option)
  args = M.options.args and M.options.args(params.bufnr, args) or args
  return args
end

---Parse a single line of Zig test plain text output and send structured events
---@param line string
---@param send fun(data: CmdData)
---@param params ZigRunParams
M.handle_output = function(line, send, params)
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
    params.output_state.current_failing_test = test_name
    params.output_state.current_error_message = error_msg

    -- Find test in results array
    local test_result = nil
    for _, tr in ipairs(params.output_state.tests_progress) do
      if tr.name == test_name then
        test_result = tr
        break
      end
    end

    -- Only mark test as failed if we haven't already
    if not test_result or test_result.status ~= "failed" then
      -- Send test_started first if we haven't seen this test before
      if not test_result then
        -- Send "running" status to storage (semantic: test was running when we became aware of it)
        send({
          type = "test_started",
          test_name = test_name,
          status = "running",
        })
        -- Store "failed" status in parsing state (to remember: waiting for location from stack trace)
        -- The status field here is a parsing phase indicator, not the test result status
        table.insert(params.output_state.tests_progress, {
          name = test_name,
          status = "failed", -- Parsing state: "saw FAIL, waiting for location line"
        })
      else
        -- Don't send test_result yet - wait for stack trace to get location
        test_result.status = "failed"
      end
    end
    return
  end

  -- Parse skipped tests
  -- Format: 2/2 server_test.test.333...SKIP
  local skip_test_name = clean_line:match("^%d+/%d+ (.-)%.%.%.SKIP%s*$")
  if skip_test_name then
    -- Extract just the test name (remove the module prefix)
    local test_name = skip_test_name:match("%.test%.(.+)$") or skip_test_name

    -- Find test in state by matching BOTH extracted name and full name
    -- (pre-populated tests might use either format depending on treesitter)
    local test_index = nil
    local location = nil
    for i, tr in ipairs(params.output_state.tests_progress) do
      if tr.name == test_name or tr.name == skip_test_name then
        test_index = i
        test_name = tr.name  -- Use the actual name from state for events
        break
      end
    end

    -- If test wasn't pre-populated, send test_started first
    if not test_index then
      send({
        type = "test_started",
        test_name = test_name,
        status = "running",
      })
    end

    -- Try to find location using treesitter
    if params.bufnr and vim.api.nvim_buf_is_valid(params.bufnr) then
      local line_no = ts.get_test_def_line_no(params.bufnr, test_name)
      if line_no then
        local file_path = vim.api.nvim_buf_get_name(params.bufnr)
        location = file_path .. ":" .. (line_no + 1)
      end
    end

    -- Send test_result for skipped test
    send({
      type = "test_result",
      test_name = test_name,
      status = "skipped",
      location = location,
    })

    -- Remove from state if it was there
    if test_index then
      table.remove(params.output_state.tests_progress, test_index)
    end

    return
  end

  -- Parse test location from stack trace
  -- Format: /path/to/test.zig:15:5: 0x100b5c857 in test.failed test (test)
  -- This line comes after the FAIL line, so we use current_failing_test
  -- We match the line that contains the exact test name
  if params.output_state.current_failing_test then
    -- Only process lines that start with a path (stack trace lines)
    if clean_line:match("^/") then
      -- Escape special pattern characters in test name for matching
      local escaped_test_name = params.output_state.current_failing_test:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
      -- Match line that contains "in test.<exact_test_name>"
      local pattern = "^([^:]+%.zig):(%d+):%d+:.* in test%." .. escaped_test_name .. " %("
      local file_path, line_str = clean_line:match(pattern)
      if file_path and line_str then
        local line_no = tonumber(line_str)

        -- Send assert_failure event for quickfix list
        send({
          type = "assert_failure",
          test_name = params.output_state.current_failing_test,
          full_path = file_path,
          line = line_no,
          message = params.output_state.current_error_message or "",
        })

        -- Also send test_result with location
        local location = file_path .. ":" .. line_str
        send({
          type = "test_result",
          test_name = params.output_state.current_failing_test,
          status = "failed",
          location = location,
        })

        -- Remove completed test from state (no longer needed for parsing)
        for i, tr in ipairs(params.output_state.tests_progress) do
          if tr.name == params.output_state.current_failing_test then
            table.remove(params.output_state.tests_progress, i)
            break
          end
        end

        params.output_state.current_failing_test = nil -- Reset after finding location
        params.output_state.current_error_message = nil
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
  local env = adapter_args.merge_env(M.options, params.bufnr)

  local all_output = {}

  -- Helper function to collect output
  local function process_output(data)
    table.insert(all_output, data)

    -- Always send as "stdout" so the colorizer can parse ANSI codes properly
    -- The UI treats "stderr" as errors and highlights everything in red,
    -- stripping ANSI codes. By sending as "stdout", we get proper color parsing.
    -- The strategy will handle line-by-line parsing via handle_output.
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
      table.insert(params.output_state.tests_progress, {
        name = test_name,
        status = "running",
      })
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
        local passed_tests, skipped_tests, failed_tests =
          clean_output:match("(%d+) passed; (%d+) skipped; (%d+) failed%.")
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
              -- Find test in results array
              local test_result = nil
              local test_index = nil
              for i, tr in ipairs(params.output_state.tests_progress) do
                if tr.name == test_name then
                  test_result = tr
                  test_index = i
                  break
                end
              end

              if test_result then
                -- For tests still "running", mark as passed
                if test_result.status == "running" then
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
                  -- Remove completed test from state
                  table.remove(params.output_state.tests_progress, test_index)
                -- For tests marked as "failed" but location not yet sent, send without location
                elseif test_result.status == "failed" then
                  send({
                    type = "test_result",
                    test_name = test_name,
                    status = "failed",
                  })
                  -- Remove completed test from state
                  table.remove(params.output_state.tests_progress, test_index)
                end
              end
            end
          else
            -- For run_all without specific test names, create generic test entries
            -- These are immediately completed, so no need to add to state
            local passed_count = passed_tests
            for i = 1, passed_count do
              local generic_name = "test_" .. i
              -- Send test_started first
              send({
                type = "test_started",
                test_name = generic_name,
                status = "running",
              })
              -- Then send test_result (completed immediately, no state tracking needed)
              send({
                type = "test_result",
                test_name = generic_name,
                status = "passed",
              })
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
  local additional_args = adapter_args.merge_additional_args(M.options, bufnr, params.opts)
  local env = adapter_args.merge_env(M.options, bufnr)

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

adapter_args.setmeta(M)

return M
