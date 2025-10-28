local ts = require("quicktest.adapters.golang.ts")
local cmd = require("quicktest.adapters.golang.cmd")
local fs = require("quicktest.fs_utils")
local Job = require("plenary.job")
local core = require("quicktest.strategies.core")
local adapter_args = require("quicktest.adapters.args")

---@class GoAdapterOptions
---@field cwd (fun(bufnr: integer, current: string?): string)?
---@field bin (fun(bufnr: integer, current: string?): string)?
---@field additional_args (fun(bufnr: integer): string[])?
---@field args (fun(bufnr: integer, current: string[]): string[])?
---@field env (fun(bufnr: integer, current: table<string, string>): table<string, string>)?
---@field is_enabled (fun(bufnr: integer, type: RunType, current: boolean): boolean)?
---@field dap (fun(bufnr: integer, params: GoRunParams): table)?

local M = {
  name = "go",
  ---@type GoAdapterOptions
  options = {},
}

local default_dap_opt = function(bufnr, params)
  return {
    showLog = true,
    logLevel = "debug",
    dlvToolPath = vim.fn.exepath("dlv"),
  }
end

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

---@class GoLogEntry
---@field Action '"start"' | '"run"' | '"pause"' | '"cont"' | '"pass"' | '"bench"' | '"fail"' | '"output"' | '"skip"'
---@field Package string
---@field Time string
---@field Test? string
---@field Output? string
---@field Elapsed? number

---@class GoRunParams
---@field func_names string[]
---@field sub_func_names string[]
---@field cwd string
---@field module string
---@field bufnr integer
---@field cursor_pos integer[]
---@field opts AdapterRunOpts

---@class GoOutputState
---@field running_tests string[]

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
---@return GoRunParams | nil, string | nil
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
---@return GoRunParams | nil, string | nil
M.build_line_run_params = function(bufnr, cursor_pos, opts)
  local func_names = ts.get_nearest_func_names(bufnr, cursor_pos)
  local sub_test_name = ts.get_sub_testcase_name(bufnr, cursor_pos) or ts.get_table_test_name(bufnr, cursor_pos)

  --- @type string[]
  local sub_func_names = {}
  if sub_test_name then
    sub_func_names = { sub_test_name }
  end

  local cwd = M.get_cwd(bufnr)
  local module = get_module_path(cwd, bufnr) or "."

  if not func_names or #func_names == 0 then
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
---@return GoRunParams | nil, string | nil
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
---@return GoRunParams | nil, string | nil
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

---Parse a single line of Go test plain text output and send structured events
---@param line string
---@param send fun(data: CmdData)
---@param params GoRunParams
---@param state GoOutputState
M.handle_output = function(line, send, params, state)
  -- Check for test start (=== RUN)
  local run_test_name = line:match("^=== RUN%s+(.+)$")
  if run_test_name then
    -- Test started - track it and send event
    table.insert(state.running_tests, run_test_name)

    -- Find test location for navigation
    local location = M.find_test_location(run_test_name, params)

    send({
      type = "test_started",
      test_name = run_test_name,
      status = "running",
      location = location,
    })
    return
  end

  -- Check for test completion (--- PASS/FAIL/SKIP)
  local test_name_pass = line:match("^%-%-%-%s+PASS:%s+([^%(]+)")
  local test_name_fail = line:match("^%-%-%-%s+FAIL:%s+([^%(]+)")
  local test_name_skip = line:match("^%-%-%-%s+SKIP:%s+([^%(]+)")

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
    -- Remove trailing whitespace from test_name
    test_name = test_name:gsub("%s+$", "")

    -- Remove from running tests
    for i, running_test in ipairs(state.running_tests) do
      if running_test == test_name then
        table.remove(state.running_tests, i)
        break
      end
    end

    -- Find test location for navigation and diagnostics
    local location = M.find_test_location(test_name, params)

    -- Send event with location
    send({
      type = "test_result",
      test_name = test_name,
      status = status,
      location = location,
    })
    return
  end

  -- Parse assert failure locations and messages from output

  -- Pattern: "Error Trace:" with full path - most important for location
  local full_path, line_str = line:match("Error Trace:%s*([^:]+):(%d+)")
  if full_path and line_str then
    local line_no = tonumber(line_str)
    -- Associate with the most recent running test
    local current_test = state.running_tests[#state.running_tests]
    if current_test then
      send({
        type = "assert_failure",
        test_name = current_test,
        full_path = full_path,
        line = line_no,
        message = "",
      })
    end
    return
  end

  -- Parse "Error:" field to get the main error message
  local error_message = line:match("Error:%s*(.+)$")
  if error_message then
    error_message = error_message:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
    -- Associate with the most recent running test
    local current_test = state.running_tests[#state.running_tests]
    if current_test then
      send({
        type = "assert_error",
        test_name = current_test,
        message = error_message,
      })
    end
    return
  end

  -- Pattern: "Messages:" to get the additional message
  local assert_message = line:match("Messages:%s*(.+)$")
  if assert_message then
    assert_message = assert_message:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
    -- Associate with the most recent running test
    local current_test = state.running_tests[#state.running_tests]
    if current_test then
      send({
        type = "assert_message",
        test_name = current_test,
        message = assert_message,
      })
    end
    return
  end
end

---@param params GoRunParams
---@param send fun(data: CmdData)
---@return integer
M.run = function(params, send)
  local additional_args = adapter_args.merge_additional_args(M.options, params.bufnr, params.opts)
  local args = cmd.build_args(params.module, params.func_names, params.sub_func_names, additional_args)
  args = M.options.args and M.options.args(params.bufnr, args) or args

  local bin = M.get_bin(params.bufnr)

  local env = adapter_args.merge_env(M.options, params.bufnr)

  -- Create output state for handle_output (strategy will use this)
  params.output_state = core.create_output_state()

  local job = Job:new({
    command = bin,
    args = args,
    env = env,
    cwd = params.cwd,
    on_stdout = function(_, data)
      send({ type = "stdout", raw = data, output = data })
    end,
    on_stderr = function(_, data)
      send({ type = "stderr", raw = data, output = data })
    end,
    on_exit = function(_, return_val)
      send({ type = "exit", code = return_val })
    end,
  })
  job:start()

  ---@type integer
  ---@diagnostic disable-next-line: assign-type-mismatch
  local pid = job.pid

  return pid
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
---@param params GoRunParams
---@return string?
M.find_test_location = function(test_name, params)
  -- Check if this is a sub-test (contains "/")
  if test_name:match("/") then
    local parent_test_name, sub_test_name = test_name:match("^([^/]+)/(.+)$")

    if parent_test_name and sub_test_name then
      -- First find the file containing the parent test
      local file_path, parent_line = find_test_location(parent_test_name, params.cwd, params.module)
      if file_path and parent_line then
        -- Load the file into a buffer to search for sub-test location
        local temp_bufnr = vim.fn.bufadd(file_path)
        vim.fn.bufload(temp_bufnr)

        -- Try to find sub-test location (t.Run calls)
        local sub_test_line = ts.find_sub_test_location(temp_bufnr, parent_test_name, sub_test_name)
        if sub_test_line then
          return file_path .. ":" .. (sub_test_line + 1) -- Convert from 0-based to 1-based
        end

        -- Try to find table-driven test case location
        local table_test_line = ts.find_table_test_case_location(temp_bufnr, parent_test_name, sub_test_name)
        if table_test_line then
          return file_path .. ":" .. (table_test_line + 1) -- Convert from 0-based to 1-based
        end

        -- If sub-test location not found, fall back to parent test location
        return file_path .. ":" .. parent_line
      end
    end
  end

  -- Regular test function (not a sub-test)
  local file_path, line_no = find_test_location(test_name, params.cwd, params.module)
  if file_path and line_no then
    return file_path .. ":" .. line_no
  end
  return nil
end

---@param bufnr integer
---@param params GoRunParams
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

--- Adapter options.
setmetatable(M, {
  ---@param opts GoAdapterOptions
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
