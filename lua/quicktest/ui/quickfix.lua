local storage = require("quicktest.storage")

---@class QuickfixConfig
---@field enabled boolean
---@field open boolean

---@param opts QuickfixConfig?
---@return table
return function(opts)
  opts = opts or {}
  
  local M = {}
  M.name = "quickfix"
  
  -- Configuration with defaults
  M.config = vim.tbl_deep_extend("force", {
    enabled = true,
    open = true
  }, opts)

local storage_subscription = nil

-- Initialize quickfix list and subscribe to storage events
function M.init()
  if storage_subscription then
    return -- Already initialized
  end
  
  storage_subscription = function(event_type, data)
    if event_type == 'test_finished' then
      M.update_quickfix()
    end
  end
  
  storage.subscribe(storage_subscription)
end

-- Clean up quickfix subscription
function M.cleanup()
  if storage_subscription then
    storage.unsubscribe(storage_subscription)
    storage_subscription = nil
  end
end

-- Update quickfix list with test results
function M.update_quickfix()
  local results = storage.get_current_results()
  local qf_items = {}

  for _, result in ipairs(results) do
    if result.status == "failed" then
      -- First, add assert failures if they exist
      if result.assert_failures and #result.assert_failures > 0 then
        for _, failure in ipairs(result.assert_failures) do
          local qf_item = {
            filename = failure.full_path,
            lnum = failure.line,
            col = 1,
            text = result.name .. ": " .. (failure.error_message or failure.message or "Assertion failed"),
            type = "E"
          }
          table.insert(qf_items, qf_item)
        end
      else
        -- If no assert failures, fall back to test location
        local filename, lnum = result.location:match("^(.+):(%d+)$")
        if filename and lnum then
          -- Only include entries with proper file:line format
          lnum = tonumber(lnum) or 1
          local qf_item = {
            filename = filename,
            lnum = lnum,
            col = 1,
            text = "Test failed: " .. result.name,
            type = "E"
          }
          table.insert(qf_items, qf_item)
        end
      end
    end
  end
  
  -- Update quickfix - open if failures and config.open is true
  if #qf_items > 0 then
    vim.fn.setqflist(qf_items, "r")
    if M.config.open then
      vim.cmd("copen")
    end
  else
    -- Clear and close quickfix when no failures (only if config.open is true)
    vim.fn.setqflist({}, "r")
    if M.config.open then
      vim.cmd("cclose")
    end
  end
end

-- Manually populate quickfix list (can be called externally)
function M.populate()
  M.update_quickfix()
end

-- Clear quickfix list
function M.clear()
  vim.fn.setqflist({}, "r")
  vim.cmd("cclose")
end

  return M
end