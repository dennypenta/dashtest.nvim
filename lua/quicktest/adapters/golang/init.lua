local ts = require("quicktest.adapters.golang.ts")
local cmd = require("quicktest.adapters.golang.cmd")
local fs = require("quicktest.fs_utils")
local adapter_args = require("quicktest.adapters.args")
local logger = require("quicktest.logger")
local core = require("quicktest.strategies.core")

local M = {
  name = "go",
  ---@type AdapterOptions
  options = {},
}

--- @param bufnr integer
--- @return string | nil
local function find_cwd(bufnr)
  local buffer_name = vim.api.nvim_buf_get_name(bufnr) -- Get the current buffer's file path
  local path = vim.fn.fnamemodify(buffer_name, ":p:h") -- Get the full path of the directory containing the file

  return fs.find_ancestor_of_file(path, "go.mod")
end

-- Find the file containing a specific test function
---@param test_name string
---@param cwd string
---@param module_path string
---@return string?, integer?
local function find_test_location(test_name, cwd, module_path)
  -- Build the search path
  local search_path = cwd
  if module_path and module_path ~= "." and module_path ~= "./..." then
    search_path = cwd .. "/" .. module_path:gsub("^%./", "")
  end

  -- Find all _test.go files in the target directory
  local test_files = vim.fn.glob(search_path .. "/*_test.go", false, true)

  for _, file_path in ipairs(test_files) do
    -- Check if file exists and is readable
    if vim.fn.filereadable(file_path) == 1 then
      -- Create a temporary buffer to search in
      local temp_bufnr = vim.fn.bufadd(file_path)
      vim.fn.bufload(temp_bufnr)

      -- Try to find the test function in this file
      local line_no = ts.get_func_def_line_no(temp_bufnr, test_name)
      if line_no then
        return file_path, line_no + 1 -- Convert from 0-based to 1-based
      end
    end
  end

  return nil, nil
end

---@param cwd string
---@param bufnr integer
---@return string | nil
local function get_module_path(cwd, bufnr)
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  -- Normalize the paths to remove trailing slashes for consistency
  cwd = string.gsub(cwd, "/$", "")
  file_path = string.gsub(file_path, "/$", "")

  -- Check if the file_path starts with the cwd and extract the relative part
  if string.sub(file_path, 1, #cwd) == cwd then
    local relative_path = string.sub(file_path, #cwd + 2) -- +2 to remove the leading slash
    local module_path = "./" .. vim.fn.fnamemodify(relative_path, ":h") -- Get directory path without filename
    return module_path
  else
    return nil -- Return nil if the file_path is not under cwd
  end
end

---@param bufnr integer
---@return string
M.get_cwd = function(bufnr)
  local current = find_cwd(bufnr) or vim.fn.getcwd()

  return M.options.cwd and M.options.cwd(bufnr, current) or current
end

M.get_bin = function(bufnr)
  local current = "go"

  return M.options.bin and M.options.bin(bufnr, current) or current
end

---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return RunParams | nil, string | nil
M.build_file_run_params = function(bufnr, cursor_pos, opts)
  local cwd = M.get_cwd(bufnr)
  local module = get_module_path(cwd, bufnr) or "."

  local func_names = ts.get_func_names(bufnr)
  if not func_names or #func_names == 0 then
    return nil, "No tests to run"
  end

  return {
    func_names = func_names,
    sub_func_names = {},
    cwd = cwd,
    module = module,
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
  local func_names = ts.get_nearest_func_names(bufnr, cursor_pos)
  local sub_test_name = ts.get_sub_testcase_name(bufnr, cursor_pos) or ts.get_table_test_name(bufnr, cursor_pos)

  logger.debug_context("adapters.golang", string.format("Found func_names: %s", vim.inspect(func_names)))
  logger.debug_context("adapters.golang", string.format("Found sub_test_name: %s", sub_test_name or "nil"))

  --- @type string[]
  local sub_func_names = {}
  if sub_test_name then
    sub_func_names = { sub_test_name }
  end

  local cwd = M.get_cwd(bufnr)
  local module = get_module_path(cwd, bufnr) or "."

  logger.debug_context("adapters.golang", string.format("cwd: %s, module: %s", cwd, module))

  if not func_names or #func_names == 0 then
    logger.debug_context("adapters.golang", "No tests to run")
    return nil, "No tests to run"
  end

  return {
    func_names = func_names,
    sub_func_names = sub_func_names,
    cwd = cwd,
    module = module,
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
  local module = "./..."

  return {
    func_names = {},
    sub_func_names = {},
    cwd = cwd,
    module = module,
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
  local module = get_module_path(cwd, bufnr) or "."

  return {
    func_names = {},
    sub_func_names = {},
    cwd = cwd,
    module = module,
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
  local args = cmd.build_args(params.module, params.func_names, params.sub_func_names, additional_args)
  args = M.options.args and M.options.args(params.bufnr, args) or args
  return args
end

---Parse a single line of Go test plain text output and send structured events
---@param line string
---@param send fun(data: CmdData)
---@param params RunParams
M.handle_output = function(line, send, params)
  logger.debug_context("adapters.golang.output", string.format("Parsing line: %s", line))

  -- Check for test start (=== RUN)
  local run_test_name = line:match("^=== RUN%s+(.+)$")
  if run_test_name then
    logger.debug_context("adapters.golang.output", string.format("Detected test start: %s", run_test_name))
    -- Test started - track it and send event
    table.insert(params.output_state.tests_progress, {
      name = run_test_name,
      status = "running",
    })
    logger.debug_context(
      "adapters.golang.output",
      string.format("Tests in progress: %d", #params.output_state.tests_progress)
    )

    -- Find test location for navigation
    local location = M.find_test_location(run_test_name, params)
    logger.debug_context("adapters.golang.output", string.format("Test location: %s", location or "nil"))

    send({
      type = "test_started",
      test_name = run_test_name,
      status = "running",
      location = location,
    })
    return
  end

  -- Check for test completion (--- PASS/FAIL/SKIP)
  -- Note: Subtests have leading whitespace/indentation
  local test_name_pass = line:match("^%s*%-%-%-%s+PASS:%s+([^%(]+)")
  local test_name_fail = line:match("^%s*%-%-%-%s+FAIL:%s+([^%(]+)")
  local test_name_skip = line:match("^%s*%-%-%-%s+SKIP:%s+([^%(]+)")

  local status, test_name
  if test_name_pass then
    status = "passed"
    test_name = test_name_pass
  elseif test_name_fail then
    status = "failed"
    test_name = test_name_fail
  elseif test_name_skip then
    status = "skipped"
    test_name = test_name_skip
  end

  if status and test_name then
    logger.debug_context(
      "adapters.golang.output",
      string.format("Detected test completion: %s [%s]", test_name, status)
    )

    -- Remove trailing whitespace from test_name
    test_name = test_name:gsub("%s+$", "")

    -- Find test location for navigation and diagnostics
    local location = M.find_test_location(test_name, params)
    logger.debug_context("adapters.golang.output", string.format("Test location: %s", location or "nil"))

    -- Send event with location
    send({
      type = "test_result",
      test_name = test_name,
      status = status,
      location = location,
    })

    core.remove_test_from_state(params.output_state, test_name)
    return
  end

  -- Parse assert failure locations and messages from output

  -- Pattern: "Error Trace:" with full path - most important for location
  local full_path, line_str = line:match("Error Trace:%s*([^:]+):(%d+)")
  if full_path and line_str then
    logger.debug_context("adapters.golang.output", string.format("Detected Error Trace: %s:%s", full_path, line_str))
    local line_no = tonumber(line_str)
    -- Associate with the most recent running test
    local current_test = nil
    for i = #params.output_state.tests_progress, 1, -1 do
      if params.output_state.tests_progress[i].status == "running" then
        current_test = params.output_state.tests_progress[i].name
        break
      end
    end
    if current_test then
      logger.debug_context(
        "adapters.golang.output",
        string.format("Associated assert failure with test: %s", current_test)
      )
      send({
        type = "assert_failure",
        test_name = current_test,
        full_path = full_path,
        line = line_no,
        message = "",
      })
    else
      logger.debug_context("adapters.golang.output", "No running test found for assert failure")
    end
    return
  end

  -- Parse "Error:" field to get the main error message
  local error_message = line:match("Error:%s*(.+)$")
  if error_message then
    error_message = error_message:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
    logger.debug_context("adapters.golang.output", string.format("Detected Error message: %s", error_message))
    -- Associate with the most recent running test
    local current_test = nil
    for i = #params.output_state.tests_progress, 1, -1 do
      if params.output_state.tests_progress[i].status == "running" then
        current_test = params.output_state.tests_progress[i].name
        break
      end
    end
    if current_test then
      logger.debug_context("adapters.golang.output", string.format("Associated error with test: %s", current_test))
      send({
        type = "assert_error",
        test_name = current_test,
        message = error_message,
      })
    else
      logger.debug_context("adapters.golang.output", "No running test found for error message")
    end
    return
  end

  -- Pattern: "Messages:" to get the additional message
  local assert_message = line:match("Messages:%s*(.+)$")
  if assert_message then
    assert_message = assert_message:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
    logger.debug_context("adapters.golang.output", string.format("Detected Messages: %s", assert_message))
    -- Associate with the most recent running test
    local current_test = nil
    for i = #params.output_state.tests_progress, 1, -1 do
      if params.output_state.tests_progress[i].status == "running" then
        current_test = params.output_state.tests_progress[i].name
        break
      end
    end
    if current_test then
      logger.debug_context("adapters.golang.output", string.format("Associated message with test: %s", current_test))
      send({
        type = "assert_message",
        test_name = current_test,
        message = assert_message,
      })
    else
      logger.debug_context("adapters.golang.output", "No running test found for assert message")
    end
    return
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
    adapter_name = "adapters.golang",
    bin = bin,
    args = args,
    env = env,
    cwd = params.cwd,
    send = send,
  })
end

M.title = function(params)
  local additional_args = adapter_args.merge_additional_args(M.options, params.bufnr, params.opts)
  local args = cmd.build_args(params.module, params.func_names, params.sub_func_names, additional_args)
  args = M.options.args and M.options.args(params.bufnr, args) or args

  return "Running test: " .. table.concat({ unpack(args, 2) }, " ")
end

---@param bufnr integer
---@param type RunType
---@return boolean
M.is_enabled = function(bufnr, type)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local is_test_file = false
  if type == "line" or type == "file" then
    is_test_file = vim.endswith(bufname, "_test.go")
  else
    is_test_file = vim.endswith(bufname, ".go")
  end

  if M.options.is_enabled == nil then
    return is_test_file
  end

  return M.options.is_enabled(bufnr, type, is_test_file)
end

---@param test_name string
---@param params RunParams
---@return string?
M.find_test_location = function(test_name, params)
  -- Check if this is a sub-test (contains "/")
  if test_name:match("/") then
    logger.debug_context("adapters.golang", "Test is a subtest, searching for parent and sub-test")
    local parent_test_name, sub_test_name = test_name:match("^([^/]+)/(.+)$")

    if parent_test_name and sub_test_name then
      logger.debug_context("adapters.golang", string.format("Parent: %s, Sub: %s", parent_test_name, sub_test_name))
      -- First find the file containing the parent test
      local file_path, parent_line = find_test_location(parent_test_name, params.cwd, params.module)
      if file_path and parent_line then
        logger.debug_context("adapters.golang", string.format("Found parent at %s:%d", file_path, parent_line))
        -- Load the file into a buffer to search for sub-test location
        local temp_bufnr = vim.fn.bufadd(file_path)
        vim.fn.bufload(temp_bufnr)

        -- Try to find sub-test location (t.Run calls)
        local sub_test_line = ts.find_sub_test_location(temp_bufnr, parent_test_name, sub_test_name)
        if sub_test_line then
          local location = file_path .. ":" .. (sub_test_line + 1)
          logger.debug_context("adapters.golang", string.format("Found sub-test t.Run location: %s", location))
          return location -- Convert from 0-based to 1-based
        end

        -- Try to find table-driven test case location
        local table_test_line = ts.find_table_test_case_location(temp_bufnr, parent_test_name, sub_test_name)
        if table_test_line then
          local location = file_path .. ":" .. (table_test_line + 1)
          logger.debug_context("adapters.golang", string.format("Found table test location: %s", location))
          return location -- Convert from 0-based to 1-based
        end

        -- If sub-test location not found, fall back to parent test location
        local fallback = file_path .. ":" .. parent_line
        logger.debug_context(
          "adapters.golang",
          string.format("Sub-test not found, using parent location: %s", fallback)
        )
        return fallback
      else
        logger.debug_context("adapters.golang", "Parent test location not found")
      end
    end
  end

  -- Regular test function (not a sub-test)
  logger.debug_context("adapters.golang", "Searching for regular test function")
  local file_path, line_no = find_test_location(test_name, params.cwd, params.module)
  if file_path and line_no then
    local location = file_path .. ":" .. line_no
    logger.debug_context("adapters.golang", string.format("Found test location: %s", location))
    return location
  end
  logger.debug_context("adapters.golang", "Test location not found")
  return nil
end

---@param bufnr integer
---@param params RunParams
---@return table?
M.build_dap_config = function(bufnr, params)
  if params.module == "./..." then
    vim.notify(
      "DAP strategy cannot debug 'all tests' across multiple packages. Use run_dir on a specific package or switch to default strategy.",
      vim.log.levels.ERROR
    )
    return
  end

  local additional_args = adapter_args.merge_additional_args(M.options, bufnr, params.opts)
  local test_args = cmd.build_dap_args(params.func_names, params.sub_func_names, additional_args)
  local env = adapter_args.merge_env(M.options, bufnr)

  local config = {
    type = "go",
    name = "Debug Test",
    request = "launch",
    mode = "test",
    program = params.module,
    args = test_args,
    env = env,
    cwd = params.cwd,
  }

  if M.options.dap then
    config = vim.tbl_extend("force", config, M.options.dap(bufnr, params))
  end

  return config
end

adapter_args.setmeta(M)

return M
