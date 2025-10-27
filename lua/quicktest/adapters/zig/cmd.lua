local M = {}

--- @param test_names string[]
--- @param test_filter_option string
--- @return string[]
local function build_test_filter_args(test_names, test_filter_option)
  if #test_names == 0 then
    return {}
  end

  -- Zig supports multiple test filters by passing multiple -Dtest-filter arguments
  local filter_args = {}
  for _, test_name in ipairs(test_names) do
    -- Don't add quotes here - plenary.job passes args directly without shell parsing
    table.insert(filter_args, string.format("-D%s=%s", test_filter_option, test_name))
  end

  return filter_args
end

--- @param test_names string[]
--- @param additional_args string[]
--- @param test_filter_option string
--- @return string[]
function M.build_args(cmd_override, test_names, additional_args, test_filter_option)
  local args = {
    "build",
    "test",
    "--summary",
    "all",
  }
  if cmd_override then
    args = vim.deepcopy(cmd_override)
  end

  local filter_args = build_test_filter_args(test_names, test_filter_option)
  args = vim.list_extend(args, filter_args)

  args = vim.list_extend(args, additional_args)

  return args
end

--- @param test_names string[]
--- @param additional_args string[]
--- @param test_filter_option string
--- @return string[]
function M.build_dap_args(test_names, additional_args, test_filter_option)
  -- For DAP, we need to pass the test filter as part of the program args
  local args = {
    "test",
    "--summary",
    "all",
  }

  local filter_args = build_test_filter_args(test_names, test_filter_option)
  args = vim.list_extend(args, filter_args)

  args = vim.list_extend(args, additional_args)

  return args
end

return M
