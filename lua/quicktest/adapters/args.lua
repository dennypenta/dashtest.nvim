local M = {}

--- Merge additional_args from adapter options and run opts
--- 1. Getting additional_args from adapter options (if configured)
--- 2. Extending with additional_args from run opts (if provided)
--- @param options table Adapter options table (e.g., M.options)
--- @param bufnr integer Buffer number for context
--- @param run_opts AdapterRunOpts Run options containing potential additional_args
--- @return string[] Merged array of additional arguments
M.merge_additional_args = function(options, bufnr, run_opts)
  local additional_args = options.additional_args and options.additional_args(bufnr) or {}
  additional_args = run_opts.additional_args and vim.list_extend(additional_args, run_opts.additional_args)
    or additional_args
  return additional_args
end

--- Merge environment variables with adapter options override
--- @param options table Adapter options table (e.g., M.options)
--- @param bufnr integer Buffer number for context
--- @return table<string, string> Merged environment variables
M.merge_env = function(options, bufnr)
  local env = vim.fn.environ()
  return options.env and options.env(bufnr, env) or env
end

return M
