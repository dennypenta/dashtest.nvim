local M = {}

M.log_file = vim.fn.stdpath("cache") .. "/dashtest.log"
M.enabled = false
M.time_format = "%H:%M:%S"
M.trace = false

local init_msg = "=== initialized ==="

local function write(msg, mode)
  local f = io.open(M.log_file, mode or "a")
  if not f then
    return vim.notify("can't open log file=" .. M.log_file, vim.log.levels.ERROR)
  end
  f:write(string.format("[%s] %s\n", os.date(M.time_format), msg))
  f:close()
end

--- Initialize logger with debug flag
---@param debug boolean
function M.init(debug)
  M.enabled = debug or false
  if M.enabled then
    write(init_msg, "w")
  end
end

--- Log debug message
---@param msg string
function M.debug(msg)
  if M.enabled then
    write(msg)
  end
end

--- Log with context (adds prefix to message)
---@param context string
---@param msg string
function M.debug_context(context, msg)
  if M.enabled then
    write(string.format("[%s] %s", context, msg))
  end
end

return M
