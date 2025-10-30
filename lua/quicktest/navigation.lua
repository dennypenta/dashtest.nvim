-- Navigation utilities for jumping to test locations
local M = {}
local logger = require("quicktest.logger")

-- Helper to find appropriate target window (avoid summary/panel windows)
local function find_target_window()
  logger.debug_context("navigation", "Finding target window")

  -- Always find the main editor window (not summary, not panel)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local win_buf = vim.api.nvim_win_get_buf(win)
      local buf_name = vim.api.nvim_buf_get_name(win_buf)
      local is_panel = vim.w[win].quicktest_panel
      local is_summary = vim.w[win].quicktest_summary

      -- Skip our special windows
      if not string.match(buf_name, "quicktest://") and not is_panel and not is_summary then
        logger.debug_context("navigation", string.format("Found suitable window: %d", win))
        return win
      end
    end
  end

  -- If no suitable window found, create a new one
  logger.debug_context("navigation", "No suitable window found, creating new")
  vim.cmd("new")
  local new_win = vim.api.nvim_get_current_win()
  logger.debug_context("navigation", string.format("Created new window: %d", new_win))
  return new_win
end

-- Discover test location with fallback logic (same for all callers)
local function discover_test_location(test)
  logger.debug_context("navigation", string.format("Discovering location for test: %s", test and test.name or "nil"))

  if not test or not test.name then
    logger.debug_context("navigation", "Test or test.name is nil")
    return nil
  end

  if test.location and test.location ~= "" then
    logger.debug_context("navigation", string.format("Using direct location: %s", test.location))
    return test.location
  end

  -- Try to find location from the "Running test:" entry
  logger.debug_context("navigation", "Searching for location in 'Running test:' entries")
  local storage = require("quicktest.storage")
  local raw_results = storage.get_current_results()
  for _, result in ipairs(raw_results) do
    if result.name and string.match(result.name, "^Running test:") and result.location and result.location ~= "" then
      local test_name_pattern = test.name
      if string.match(test.name, "/") then
        -- For sub-tests, use the parent test name
        test_name_pattern = string.match(test.name, "^([^/]+)")
        logger.debug_context("navigation", string.format("Using parent test pattern: %s", test_name_pattern))
      end

      if string.match(result.name, test_name_pattern) then
        logger.debug_context("navigation", string.format("Found location from Running test: %s", result.location))
        return result.location
      end
    end
  end

  -- If still no location, look through all results for parent test
  if string.match(test.name, "/") then
    local parent_name = string.match(test.name, "^([^/]+)")
    logger.debug_context("navigation", string.format("Searching for parent test: %s", parent_name))

    for _, result in ipairs(raw_results) do
      if result.name == parent_name and result.location and result.location ~= "" then
        logger.debug_context("navigation", string.format("Found location from parent test: %s", result.location))
        return result.location
      end
    end
  end

  logger.debug_context("navigation", "No location found")
  return nil
end

-- Navigate to test location with basic function discovery
---@param test TestResult
---@param callback function? Optional callback to run after navigation
---@return boolean success
function M.jump_to_test(test, callback)
  if not test then
    logger.debug_context("navigation", "No test provided")
    return false
  end

  local location = discover_test_location(test)
  if not location then
    logger.debug_context("navigation", "No location discovered for test")
    return false
  end

  local parts = vim.split(location, ":")
  if #parts < 1 then
    logger.debug_context("navigation", "Invalid location format")
    return false
  end

  local file = parts[1]
  local line = tonumber(parts[2]) or 1
  logger.debug_context("navigation", string.format("Jumping to %s:%d", file, line))

  local target_win = find_target_window()
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_win_call(target_win, function()
      vim.cmd("edit " .. vim.fn.fnameescape(file))

      local bufnr = vim.api.nvim_get_current_buf()

      -- If no specific line number, try to find the test function
      if line == 1 and test and test.name then
        logger.debug_context("navigation", "No specific line, searching for test function")
        local test_name = test.name

        -- For Go sub-tests, use the parent test name to find the function
        if string.match(test_name, "/") then
          test_name = string.match(test_name, "^([^/]+)")
          logger.debug_context("navigation", string.format("Searching for parent function: %s", test_name))
        end

        -- Search for the test function definition
        local search_pattern = "func " .. test_name .. "("
        local found_line = vim.fn.search("\\V" .. vim.fn.escape(search_pattern, "\\"), "nw")

        if found_line > 0 then
          line = found_line
          logger.debug_context("navigation", string.format("Found test function at line %d", line))
        else
          logger.debug_context("navigation", "Test function not found")
        end
      end

      -- Validate line number is within buffer bounds
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      if line > line_count then
        logger.debug_context("navigation", string.format("Line %d exceeds buffer bounds, clamping to %d", line, line_count))
        line = line_count
      end
      if line < 1 then
        logger.debug_context("navigation", "Line < 1, clamping to 1")
        line = 1
      end

      vim.api.nvim_win_set_cursor(0, { line, 0 })
      logger.debug_context("navigation", string.format("Cursor set to line %d", line))
    end)

    -- Focus the target window
    vim.api.nvim_set_current_win(target_win)

    -- Run callback if provided
    if callback then
      logger.debug_context("navigation", "Running callback")
      callback()
    end

    return true
  end

  logger.debug_context("navigation", "No valid target window")
  return false
end

return M

