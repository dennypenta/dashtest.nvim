local M = {}

--- Unified output state structure used by all strategies
--- This state is passed to adapter.handle_output() when parsing test output line-by-line.
--- All strategies MUST create state using M.create_output_state() to ensure consistency.
---
--- @class OutputState
--- used by go
--- @field running_tests string[] List of currently running test names (used by strategies and adapters)
--- used by zig
--- @field current_failing_test string? Name of the test that is currently failing (used by adapters for multi-line parsing)
--- @field current_error_message string? Error message associated with current_failing_test (used by adapters)
--- @field test_results table<string, string> Map of test_name -> status ("running", "passed", "failed", "skipped")

--- Creates a new unified output state for test execution
--- All strategies MUST use this function to create the initial state passed to handle_output().
---
--- @return OutputState
M.create_output_state = function()
  return {
    running_tests = {},
    current_failing_test = nil,
    current_error_message = nil,
    test_results = {},
  }
end

return M
