local storage = require("quicktest.storage")
local notify = require("quicktest.notify")
local a = require("plenary.async")
local u = require("plenary.async.util")
local core = require("quicktest.strategies.core")
local logger = require("quicktest.logger")

local M = {
  name = "default",
}

-- Module-level current job tracking (shared with kill function)
local current_job = nil

-- Expose kill function for external access
M.kill_current_run = function()
  if current_job and current_job.pid then
    logger.debug_context("strategies.default", string.format("Killing job with PID: %d", current_job.pid))
    local job = current_job
    vim.system({ "kill", tostring(current_job.pid) }):wait()
    current_job = nil

    local passedTime = vim.loop.now() - job.started_at
    local time_display = string.format("%.2f", passedTime / 1000) .. "s"

    storage.test_output("status", "Cancelled after " .. time_display)
    logger.debug_context("strategies.default", string.format("Job cancelled after %s", time_display))
  else
    logger.debug_context("strategies.default", "No current job to kill")
  end
end

M.is_available = function()
  return true
end

M.run = function(adapter, params, config, opts)
  if current_job then
    if current_job.pid then
      logger.debug_context("strategies.default", "Killing existing job before starting new one")
      vim.system({ "kill", tostring(current_job.pid) }):wait()
      current_job = nil
    else
      logger.debug_context("strategies.default", "Job already running, returning early")
      return notify.warn("Already running")
    end
  end

  -- Clear storage for new run
  logger.debug_context("strategies.default", "Clearing storage for new run")
  storage.clear()

  --- @type {id: number, started_at: number, pid: number?, exit_code: number?}
  local job = { id = math.random(10000000000000000), started_at = vim.uv.now() }
  current_job = job
  logger.debug_context("strategies.default", string.format("Created new job with ID: %d", job.id))

  local is_running = function()
    return current_job and job.id == current_job.id
  end

  params.output_state = core.create_output_state()

  local runLoop = function()
    logger.debug_context("strategies.default", "Starting run loop")
    local sender, receiver = a.control.channel.mpsc()
    local pid = adapter.run(params, function(data)
      sender.send(data)
    end)
    job.pid = pid
    logger.debug_context("strategies.default", string.format("Adapter started with PID: %d", pid))

    -- Start test event
    local test_name = "Test"
    local test_location = ""

    if adapter.title then
      test_name = adapter.title(params)
    end

    if params and params.bufnr then
      test_location = vim.api.nvim_buf_get_name(params.bufnr)
      if params.line_number then
        test_location = test_location .. ":" .. params.line_number
      end
    end

    logger.debug_context("strategies.default", string.format("Test started: %s at %s", test_name, test_location))
    storage.test_started(test_name, test_location)

    local results = {}
    local job_done = false

    -- Keep processing events even after exit, up to a reasonable limit.
    -- This drains buffered events that arrived before exit but haven't been processed yet.
    -- The 10k limit prevents infinite loops if the channel doesn't close properly.
    local events_after_exit = 0
    local MAX_EVENTS_AFTER_EXIT = 10000

    while is_running() or (job_done and events_after_exit < MAX_EVENTS_AFTER_EXIT) do
      local result = receiver.recv()
      if not result then
        logger.debug_context("strategies.default", "No more events, breaking loop")
        break -- Channel closed or no more events
      end

      table.insert(results, result)

      u.scheduler()

      if result.type == "exit" then
        logger.debug_context("strategies.default", string.format("Exit event received with code: %d", result.code))
        job.exit_code = result.code
        current_job = nil
        job_done = true

        -- Emit test finished event
        local status = result.code == 0 and "passed" or "failed"
        local duration = vim.uv.now() - job.started_at
        logger.debug_context(
          "strategies.default",
          string.format("Test finished: %s [%s] in %dms", test_name, status, duration)
        )
        storage.test_finished(test_name, status, duration)

        if adapter.after_run then
          logger.debug_context("strategies.default", "Running adapter after_run hook")
          adapter.after_run(params, results)
        end
      end
      if job_done then
        events_after_exit = events_after_exit + 1
      end

      if result.type == "stdout" and result.output then
        storage.test_output("stdout", result.output)
        -- Let adapter parse output line by line if it has handle_output
        if adapter.handle_output and params.output_state then
          local lines = vim.split(result.output, "\n", { plain = true })
          for _, line in ipairs(lines) do
            if line ~= "" then
              -- Adapter will emit events via sender, which will be processed by handlers below
              adapter.handle_output(line, sender.send, params)
            end
          end
        end
      elseif result.type == "stderr" and result.output then
        storage.test_output("stderr", result.output)
      elseif result.type == "test_started" then
        logger.debug_context("strategies.default", string.format("Event: test_started [%s]", result.test_name))
        -- Handle individual test start from adapter
        -- Use location from event if provided, otherwise try to find it
        local location = result.location or ""
        if location == "" and adapter.find_test_location then
          location = adapter.find_test_location(result.test_name, params) or ""
        end
        storage.test_started(result.test_name, location)
      elseif result.type == "test_result" then
        logger.debug_context(
          "strategies.default",
          string.format("Event: test_result [%s] status=%s", result.test_name, result.status)
        )
        -- Handle individual test results from adapter
        -- Use location from event if provided, otherwise try to find it
        local location = result.location or ""
        if location == "" and adapter.find_test_location then
          location = adapter.find_test_location(result.test_name, params) or ""
        end
        -- Mark test as finished (it should already exist from test_started)
        storage.test_finished(result.test_name, result.status, nil, location)
      elseif result.type == "assert_failure" then
        logger.debug_context(
          "strategies.default",
          string.format("Event: assert_failure [%s] at %s:%d", result.test_name, result.full_path, result.line)
        )
        -- Handle assert failure location information
        storage.assert_failure(result.test_name, result.full_path, result.line, result.message)
      elseif result.type == "assert_error" then
        logger.debug_context("strategies.default", string.format("Event: assert_error [%s]", result.test_name))
        -- Handle assert error message (main error description)
        storage.assert_error(result.test_name, result.message)
      elseif result.type == "assert_message" then
        logger.debug_context("strategies.default", string.format("Event: assert_message [%s]", result.test_name))
        -- Handle assert failure message to override previous message
        storage.assert_message(result.test_name, result.message)
      end
    end
    logger.debug_context("strategies.default", "Run loop completed")
  end

  ---@diagnostic disable-next-line: missing-parameter
  a.run(function()
    xpcall(runLoop, function(err)
      logger.debug_context("strategies.default", string.format("Error in async job: %s", err))
      logger.debug_context("strategies.default", string.format("Stack trace: %s", debug.traceback()))
      print("Error in async job:", err)
      print("Stack trace:", debug.traceback())

      notify.error("Test run failed: " .. err)
    end)
  end)

  -- Return strategy result interface
  return {
    is_complete = function()
      return current_job == nil
    end,
    output_stream = function()
      return function()
        return nil
      end
    end,
    output = function()
      return ""
    end,
    stop = function()
      M.kill_current_run()
    end,
    result = function()
      while current_job do
        vim.wait(100)
      end
      return job.exit_code or -1
    end,
  }
end

return M
