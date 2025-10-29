local M = {}
local logger = require("quicktest.logger")

---@class QuicktestStrategyResult
---@field is_complete fun(): boolean
---@field output_stream fun(): fun(): string?
---@field output fun(): string
---@field attach? fun()
---@field stop fun()
---@field result fun(): number

---@class QuicktestStrategy
---@field name string
---@field run fun(adapter: QuicktestAdapter, params: any, config: QuicktestConfig, opts: AdapterRunOpts): QuicktestStrategyResult
---@field is_available fun(): boolean

local strategies = {}
local loaded = false

M.register = function(strategy)
  logger.debug_context("strategies.init", string.format("Registering strategy: %s", strategy.name))
  strategies[strategy.name] = strategy
end

M.get = function(name)
  if not loaded then
    M.load_strategies()
  end
  return strategies[name]
end

M.get_available = function()
  if not loaded then
    M.load_strategies()
  end
  local available = {}
  for name, strategy in pairs(strategies) do
    if strategy.is_available() then
      logger.debug_context("strategies.init", string.format("Strategy available: %s", name))
      available[name] = strategy
    else
      logger.debug_context("strategies.init", string.format("Strategy not available: %s", name))
    end
  end
  return available
end

M.load_strategies = function()
  if loaded then
    logger.debug_context("strategies.init", "Strategies already loaded")
    return
  end
  loaded = true
  logger.debug_context("strategies.init", "Loading default strategy")
  local d = require("quicktest.strategies.default")
  M.register(d)
  logger.debug_context("strategies.init", "Loading dap strategy")
  local dap = require("quicktest.strategies.dap")
  M.register(dap)
end

return M
