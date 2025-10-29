local storage = require("quicktest.storage")
local core = require("quicktest.strategies.core")
local logger = require("quicktest.logger")

local M = {
  name = "dap",
}

M.is_available = function()
  local ok, dap = pcall(require, "dap")
  return ok and dap ~= nil
end

---@param adapter QuicktestAdapter
---@param params any
---@param config QuicktestConfig
---@param opts AdapterRunOpts
---@return QuicktestStrategyResult
M.run = function(adapter, params, config, opts)

  logger.debug_context("strategies.dap", string.format("DAP strategy run started with params: %s", vim.inspect({
    adapter_name = adapter.name,
    params = params,
    opts = opts,
    has_build_dap_config = adapter.build_dap_config ~= nil,
  })))

  if not adapter.build_dap_config then
    logger.debug_context("strategies.dap", "Adapter missing build_dap_config method")
    error("Adapter does not support DAP strategy - missing build_dap_config method")
  end

  local dap = require("dap")
  logger.debug_context("strategies.dap", "Clearing storage for new DAP run")
  storage.clear()

  local handler_id = "quicktest_" .. vim.fn.localtime()
  local output_data = {}
  local is_finished = false
  local result_code = nil

  local output_path = vim.fn.tempname()
  local output_fd = nil
  logger.debug_context("strategies.dap", string.format("Output path: %s", output_path))

  params.output_state = core.create_output_state()

  -- Create wrapper send function that converts adapter events to storage calls
  local function adapter_event_to_storage(event)
    logger.debug_context("strategies.dap", string.format("Adapter event: %s", event.type))
    if event.type == "test_started" then
      storage.test_started(event.test_name, event.location or "")
    elseif event.type == "test_result" then
      storage.test_finished(event.test_name, event.status, nil, event.location)
    elseif event.type == "assert_failure" then
      storage.assert_failure(event.test_name, event.full_path, event.line, event.message or "")
    elseif event.type == "assert_error" then
      storage.assert_error(event.test_name, event.message)
    elseif event.type == "assert_message" then
      storage.assert_message(event.test_name, event.message)
    end
  end

  local function write_output(data)
    table.insert(output_data, data)
    -- Also emit to storage
    storage.test_output("stdout", data)

    -- Use adapter's handle_output if available, otherwise skip parsing
    if adapter.handle_output then
      local lines = vim.split(data, "\n", { plain = true })
      for _, line in ipairs(lines) do
        if line ~= "" then
          adapter.handle_output(line, adapter_event_to_storage, params)
        end
      end
    end

    if output_fd then
      local write_err, _ = vim.uv.fs_write(output_fd, data)
      if write_err then
        vim.notify("Failed to write DAP output: " .. write_err, vim.log.levels.WARN)
      end
    end
  end

  -- Try to open output file, but don't fail if it doesn't work
  local open_err
  open_err, output_fd = vim.uv.fs_open(output_path, "w", 438)
  if open_err then
    logger.debug_context("strategies.dap", string.format("Failed to create output file: %s", open_err))
    vim.notify("Failed to create DAP output file: " .. open_err, vim.log.levels.WARN)
    output_fd = nil
  else
    logger.debug_context("strategies.dap", "Output file created successfully")
  end

  local dap_config = adapter.build_dap_config(params.bufnr, params)
  logger.debug_context("strategies.dap", string.format("DAP config built: %s", vim.inspect(dap_config)))

  -- Get filetype for DAP configuration
  local test_bufnr = vim.fn.bufnr(params.bufnr)
  local filetype = vim.api.nvim_buf_get_option(test_bufnr, "filetype")

  logger.debug_context("strategies.dap", "Starting DAP session")
  dap.run(vim.tbl_extend("keep", dap_config, { env = dap_config.env, cwd = dap_config.cwd }), {
    filetype = filetype,
    before = function(cfg)
      logger.debug_context("strategies.dap", "DAP before callback")
      dap.listeners.after.event_output[handler_id] = function(_, body)
        if vim.tbl_contains({ "stdout", "stderr" }, body.category) then
          write_output(body.output)
        end
      end

      dap.listeners.after.event_exited[handler_id] = function(_, info)
        logger.debug_context("strategies.dap", string.format("DAP exited with code: %d", info.exitCode))
        result_code = info.exitCode
        is_finished = true

        if output_fd then
          vim.uv.fs_close(output_fd)
        end
      end

      return cfg
    end,
    after = function()
      logger.debug_context("strategies.dap", "DAP after callback")
      local received_exit = result_code ~= nil
      if not received_exit then
        logger.debug_context("strategies.dap", "No exit event received, marking as passed")
        result_code = 0
        is_finished = true

        if output_fd then
          vim.uv.fs_close(output_fd)
        end
      end
      dap.listeners.after.event_output[handler_id] = nil
      dap.listeners.after.event_exited[handler_id] = nil
      logger.debug_context("strategies.dap", "DAP listeners cleaned up")
    end,
  })

  return {
    is_complete = function()
      return is_finished
    end,
    output_stream = function()
      local index = 0
      return function()
        index = index + 1
        return output_data[index]
      end
    end,
    output = function()
      return output_path
    end,
    attach = function()
      dap.repl.open()
    end,
    stop = function()
      logger.debug_context("strategies.dap", "Stop called, terminating DAP session")
      dap.terminate()
      if not is_finished then
        logger.debug_context("strategies.dap", "Session terminated")
        result_code = -1
        is_finished = true

        if output_fd then
          vim.uv.fs_close(output_fd)
        end
      end
    end,
    result = function()
      while not is_finished do
        vim.wait(100)
      end
      return result_code or -1
    end,
  }
end

return M
