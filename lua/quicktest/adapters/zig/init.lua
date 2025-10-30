local ts = require("quicktest.adapters.zig.ts")
local cmd = require("quicktest.adapters.zig.cmd")
local fs = require("quicktest.fs_utils")
local adapter_args = require("quicktest.adapters.args")
local logger = require("quicktest.logger")

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
---@return RunParams | nil, string | nil
M.build_file_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)

  local func_names = ts.get_test_names(bufnr)

  logger.debug_context(
    "adapters.zig",
    string.format(
      "build_file_run_params: %s",
      vim.inspect({
        bufnr = bufnr,
        buf_valid = vim.api.nvim_buf_is_valid(bufnr),
        buf_loaded = vim.api.nvim_buf_is_loaded(bufnr),
        buf_name = vim.api.nvim_buf_get_name(bufnr),
        filetype = vim.api.nvim_buf_get_option(bufnr, "filetype"),
        cwd = cwd,
        test_count = func_names and #func_names or 0,
        func_names = func_names or {},
        opts = opts,
      })
    )
  )

  if not func_names or #func_names == 0 then
    return nil, "No tests to run"
  end

  return {
    func_names = func_names,
    sub_func_names = {},
    module = "",
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
---@return RunParams | nil, string | nil
M.build_line_run_params = function(bufnr, cursor_pos, opts)
  local func_names = ts.get_nearest_test_names(bufnr, cursor_pos)

  local cwd = M.get_cwd(bufnr)

  if not func_names or #func_names == 0 then
    return nil, "No tests to run"
  end

  return {
    func_names = func_names,
    sub_func_names = {},
    module = "",
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
---@return RunParams | nil, string | nil
M.build_all_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)

  return {
    func_names = {},
    sub_func_names = {},
    module = "",
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
---@return RunParams | nil, string | nil
M.build_dir_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)

  -- Collect all test names from the current buffer
  local func_names = ts.get_test_names(bufnr)

  return {
    func_names = func_names,
    sub_func_names = {},
    module = "",
    cwd = cwd,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    opts = opts,
  },
    nil
end

---@param params RunParams
---@return string[]
M.build_cmd = function(params)
  local additional_args = adapter_args.merge_additional_args(M.options, params.bufnr, params.opts)
  local test_filter_option = M.get_test_filter_option(params.bufnr)
  local args = cmd.build_args(params.opts.cmd_override, params.func_names, additional_args, test_filter_option)
  args = M.options.args and M.options.args(params.bufnr, args) or args
  return args
end

---Parse a single line of Zig test plain text output and send structured events
---@param line string
---@param send fun(data: CmdData)
---@param params RunParams
M.handle_output = function(line, send, params)
  logger.debug_context("adapters.zig.output", string.format("Parsing line: %s", line))

  -- Strip ANSI color codes for reliable parsing (especially in DAP mode)
  local clean_line = strip_ansi_codes(line)

  -- Parse passing tests
  -- Format: 1/5 server.test_0...OK
  -- Format: 2/5 server_test.test.test http server with SIGTERM...OK
  local ok_full_test_name = clean_line:match("^%d+/%d+ (.-)%.%.%.OK%s*$")
  if ok_full_test_name then
    logger.debug_context("adapters.zig.output", string.format("Detected passing test: %s", ok_full_test_name))
    -- Extract just the test name (remove the module prefix)
    local test_name = ok_full_test_name:match("%.test%.(.+)$") or ok_full_test_name

    -- Find test in state by matching BOTH extracted name and full name
    local test_index = nil
    local location = nil
    for i, tr in ipairs(params.output_state.tests_progress) do
      if tr.name == test_name or tr.name == ok_full_test_name then
        test_index = i
        test_name = tr.name -- Use the actual name from state for events
        logger.debug_context("adapters.zig.output", string.format("Found test in progress state: %s", test_name))
        break
      end
    end

    if not test_index then
      logger.debug_context("adapters.zig.output", "Test not in progress state, sending test_started")
      -- Send test_started first if test wasn't pre-populated
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
        logger.debug_context("adapters.zig.output", string.format("Found test location: %s", location))
      end
    end

    logger.debug_context("adapters.zig.output", string.format("Sending test_result: %s [passed]", test_name))
    -- Send test_result for passing test
    send({
      type = "test_result",
      test_name = test_name,
      status = "passed",
      location = location,
    })

    -- Remove from state if it was there
    if test_index then
      table.remove(params.output_state.tests_progress, test_index)
      logger.debug_context(
        "adapters.zig.output",
        string.format("Removed test from progress, remaining: %d", #params.output_state.tests_progress)
      )
    end

    return
  end

  -- Parse test failures
  -- Format: 2/3 server_test.test.11...FAIL (Jo)
  -- Note: Line may end with \r (carriage return)
  local full_test_name, error_msg = clean_line:match("^%d+/%d+ (.-)%.%.%.FAIL %((.+)%)%s*$")

  if full_test_name then
    logger.debug_context(
      "adapters.zig.output",
      string.format("Detected failing test: %s, error: %s", full_test_name, error_msg)
    )
    -- Extract just the test name (remove the module prefix)
    -- Format is typically: "module.test.test_name" or "test.test.test_name"
    local test_name = full_test_name:match("%.test%.(.+)$") or full_test_name
    params.output_state.current_failing_test = test_name
    params.output_state.current_error_message = error_msg

    logger.debug_context("adapters.zig.output", string.format("Extracted test name: %s", test_name))
    logger.debug_context("adapters.zig.output", "Waiting for stack trace to get location")

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
        logger.debug_context("adapters.zig.output", "Test not in progress, adding to state and sending test_started")
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
        logger.debug_context("adapters.zig.output", "Test in progress, marking as failed in parsing state")
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
        test_name = tr.name -- Use the actual name from state for events
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
      logger.debug_context(
        "adapters.zig.output",
        string.format("Parsing stack trace for test: %s", params.output_state.current_failing_test)
      )
      -- Escape special pattern characters in test name for matching
      local escaped_test_name = params.output_state.current_failing_test:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
      -- Match line that contains "in test.<exact_test_name>"
      local pattern = "^([^:]+%.zig):(%d+):%d+:.* in test%." .. escaped_test_name .. " %("
      local file_path, line_str = clean_line:match(pattern)
      if file_path and line_str then
        logger.debug_context(
          "adapters.zig.output",
          string.format("Found test location in stack trace: %s:%s", file_path, line_str)
        )
        local line_no = tonumber(line_str)

        -- Send assert_failure event for quickfix list
        logger.debug_context(
          "adapters.zig.output",
          string.format(
            "Sending assert_failure: %s at %s:%d",
            params.output_state.current_failing_test,
            file_path,
            line_no
          )
        )
        send({
          type = "assert_failure",
          test_name = params.output_state.current_failing_test,
          full_path = file_path,
          line = line_no,
          message = params.output_state.current_error_message or "",
        })

        -- Also send test_result with location
        local location = file_path .. ":" .. line_str
        logger.debug_context(
          "adapters.zig.output",
          string.format("Sending test_result: %s [failed] at %s", params.output_state.current_failing_test, location)
        )
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
            logger.debug_context(
              "adapters.zig.output",
              string.format("Removed test from progress, remaining: %d", #params.output_state.tests_progress)
            )
            break
          end
        end

        logger.debug_context("adapters.zig.output", "Resetting current_failing_test state")
        params.output_state.current_failing_test = nil -- Reset after finding location
        params.output_state.current_error_message = nil
      end
    end
  end
end

---@param params RunParams
---@param send fun(data: CmdData)
---@return integer
M.run = function(params, send)
  local args = M.build_cmd(params)
  local bin = M.get_bin(params.bufnr)
  local env = adapter_args.merge_env(M.options, params.bufnr)

  return adapter_args.run_job({
    adapter_name = "adapters.zig",
    bin = bin,
    args = args,
    env = env,
    cwd = params.cwd,
    send = send,
  })
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
---@param params RunParams
---@return string?
M.find_test_location = function(test_name, params)
  local file_path, line_no = find_test_location(test_name, params.cwd)
  if file_path and line_no then
    return file_path .. ":" .. line_no
  end
  return nil
end

---@param bufnr integer
---@param params RunParams
---@return table?
M.build_dap_config = function(bufnr, params)
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
