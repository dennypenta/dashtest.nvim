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

--- Base parameters shared across all adapter run implementations
--- Each adapter can extend this with their specific fields if needed
---
--- @class RunParams
--- @field func_names string[] Names of test functions to run
--- @field sub_func_names string[] Names of sub-tests/nested tests to run
--- @field module string Module or package path to run tests in
--- @field cwd string Working directory for test execution
--- @field bufnr integer Buffer number of the test file
--- @field cursor_pos integer[] Cursor position [row, col]
--- @field opts AdapterRunOpts Adapter-specific run options
--- @field output_state OutputState State for tracking test output parsing

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
