-- main module file
local module = require("quicktest.module")

local config = {
  adapters = {},
  ui = {}, -- List of UI consumers
  strategy = "default",
  debug = false,
}

---@class MyModule
local M = {}

--- @type QuicktestConfig
M.config = config

---@param args QuicktestConfig?
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})

  -- Initialize logger
  local logger = require("quicktest.logger")
  logger.init(M.config.debug or false)

  -- Initialize UI with explicit consumers
  local ui = require("quicktest.ui")
  ui.init_with_consumers(M.config.ui or {})
end

--- @param mode WinMode?
M.run_previous = function(mode)
  return module.run_previous(M.config, mode or "auto")
end

--- @param mode WinMode?
--- @param adapter Adapter?
--- @param opts AdapterRunOpts?
M.run_line = function(mode, adapter, opts)
  return module.prepare_and_run(M.config, "line", mode or "auto", adapter or "auto", opts or {})
end

--- @param mode WinMode?
--- @param adapter Adapter?
--- @param opts AdapterRunOpts?
M.run_file = function(mode, adapter, opts)
  return module.prepare_and_run(M.config, "file", mode or "auto", adapter or "auto", opts or {})
end

--- @param mode WinMode?
--- @param adapter Adapter?
--- @param opts AdapterRunOpts?
M.run_dir = function(mode, adapter, opts)
  return module.prepare_and_run(M.config, "dir", mode or "auto", adapter or "auto", opts or {})
end

--- @param mode WinMode?
--- @param adapter Adapter?
--- @param opts AdapterRunOpts?
M.run_all = function(mode, adapter, opts)
  return module.prepare_and_run(M.config, "all", mode or "auto", adapter or "auto", opts or {})
end

M.cancel_current_run = function()
  module.kill_current_run()
end

--- Get the build command for the current adapter
--- This allows external tools (like compile.nvim) to get the build command before running DAP
--- @param adapter Adapter?
--- @param opts AdapterRunOpts?
--- @return string[] | nil
M.get_build_line = function(adapter, opts)
  return module.get_build_command(M.config, "line", adapter or "auto", opts or {})
end

--- Get the build command for the current adapter
--- This allows external tools (like compile.nvim) to get the build command before running DAP
--- @param adapter Adapter?
--- @param opts AdapterRunOpts?
--- @return string[] | nil
M.get_build_file = function(adapter, opts)
  return module.get_build_command(M.config, "file", adapter or "auto", opts or {})
end

--- Get the build command for the current adapter
--- This allows external tools (like compile.nvim) to get the build command before running DAP
--- @param adapter Adapter?
--- @param opts AdapterRunOpts?
--- @return string[] | nil
M.get_build_dir = function(adapter, opts)
  return module.get_build_command(M.config, "dir", adapter or "auto", opts or {})
end

--- Get the build command for the current adapter
--- This allows external tools (like compile.nvim) to get the build command before running DAP
--- @param adapter Adapter?
--- @param opts AdapterRunOpts?
--- @return string[] | nil
M.get_build_all = function(adapter, opts)
  return module.get_build_command(M.config, "all", adapter or "auto", opts or {})
end

-- Navigate to next failed test
M.next_failed_test = function()
  local storage = require("quicktest.storage")
  local test = storage.next_failed_test()
  if not test then
    vim.notify("No failed tests found", vim.log.levels.INFO)
    return
  end

  local navigation = require("quicktest.navigation")
  navigation.jump_to_test(test)
end

-- Navigate to previous failed test
M.prev_failed_test = function()
  local storage = require("quicktest.storage")
  local test = storage.prev_failed_test()
  if not test then
    vim.notify("No failed tests found", vim.log.levels.INFO)
    return
  end

  local navigation = require("quicktest.navigation")
  navigation.jump_to_test(test)
end

return M
