local Job = require("plenary.job")
local logger = require("quicktest.logger")

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

---@class RunJobConfig
---@field adapter_name string Name of the adapter (for logging)
---@field bin string Binary to execute
---@field args string[] Command arguments
---@field env table<string, string> Environment variables
---@field cwd string Working directory
---@field send fun(data: CmdData) Callback to send test data
---@field stderr_to_stdout boolean? Whether to redirect stderr to stdout (default: false)

--- Run a test command using plenary.job with common adapter logic
--- @param config RunJobConfig Configuration for the job
--- @return integer PID of the started job
M.run_job = function(config)
  logger.debug_context(config.adapter_name, string.format("Command args: %s", vim.inspect(config.args)))
  logger.debug_context(config.adapter_name, string.format("Binary: %s", config.bin))

  local job = Job:new({
    command = config.bin,
    args = config.args,
    env = config.env,
    cwd = config.cwd,
    on_stdout = function(_, data)
      config.send({ type = "stdout", raw = data, output = data })
    end,
    on_stderr = function(_, data)
      config.send({ type = "stdout", raw = data, output = data })
    end,
    on_exit = function(_, return_val)
      logger.debug_context(config.adapter_name, string.format("Job exited with code: %d", return_val))
      config.send({ type = "exit", code = return_val })
    end,
  })
  job:start()

  ---@type integer
  ---@diagnostic disable-next-line: assign-type-mismatch
  local pid = job.pid
  logger.debug_context(config.adapter_name, string.format("Job started with PID: %d", pid))

  return pid
end

---@class AdapterOptions
---@field cwd (fun(bufnr: integer, current: string?): string)?
---@field bin (fun(bufnr: integer, current: string?): string)?
---@field additional_args (fun(bufnr: integer): string[])?
---@field args (fun(bufnr: integer, current: string[]): string[])?
---@field env (fun(bufnr: integer, current: table<string, string>): table<string, string>)?
---@field is_enabled (fun(bufnr: integer, type: RunType, current: boolean): boolean)?
---@field test_filter_option (fun(bufnr: integer, current: string): string)?
---@field dap (fun(bufnr: integer, params: RunParams): table)?

local default_dap_opt = function(bufnr, params)
  return {
    showLog = true,
    logLevel = "debug",
  }
end

function M.setmeta(adapter)
  setmetatable(adapter, {
    ---@param opts AdapterOptions
    __call = function(_, opts)
      opts = opts or {}
      if opts.dap == nil then
        opts.dap = default_dap_opt
      end
      adapter.options = opts

      return adapter
    end,
  })
end

return M
