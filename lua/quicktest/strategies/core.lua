local M = {}

--- Test result entry with name, status, and metadata
--- Note: The status field has different semantics per adapter:
--- - Go: Always "running" (tests removed from state when completed)
--- - Zig: Parsing phase indicator ("running" = normal, "failed" = waiting for location from stack trace)
--- @class TestProgress
--- @field name string The name of the test
--- @field status string Test status: "running", "passed", "failed", "skipped"

--- Unified output state structure used by all strategies
--- This state is passed to adapter.handle_output() when parsing test output line-by-line.
--- All strategies MUST create state using M.create_output_state() to ensure consistency.
---
--- @class OutputState
--- @field tests_progress TestProgress[] Array of test results with ordering (used by all adapters for status tracking)
--- @field current_failing_test string? Name of the test that is currently failing (used by Zig for multi-line parsing)
--- @field current_error_message string? Error message associated with current_failing_test (used by Zig)

--- Creates a new unified output state for test execution
--- All strategies MUST use this function to create the initial state passed to handle_output().
---
--- @return OutputState
M.create_output_state = function()
  return {
    tests_progress = {},
    current_failing_test = nil,
    current_error_message = nil,
  }
end

return M
