local M = {
  -- Query to find all test declarations
  query_test_name = [[
    (test_declaration
      (string) @test_name)
  ]],

  -- Query to find a specific test by name
  query_test_def_line_no = [[
    (test_declaration
      (string) @test_name
      (#eq? @test_name "\"%s\""))
  ]],
}

---@param bufnr integer
---@return TSNode?
local function get_root_node(bufnr)
  local parser = vim.treesitter.get_parser(bufnr, "zig")
  if not parser then
    return
  end

  local tree = parser:parse()[1]
  if not tree then
    return
  end

  return tree:root()
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return string?
function M.get_current_test_name(bufnr, cursor_pos)
  -- Convert from 1-based to 0-based indexing for treesitter
  local row, col = cursor_pos[1] - 1, cursor_pos[2]
  local node = vim.treesitter.get_node({ bufnr = bufnr, pos = { row, col } })
  if not node then
    return
  end

  -- Walk up the tree to find a test_declaration node
  while node do
    if node:type() == "test_declaration" then
      break
    end
    node = node:parent()
  end

  if not node then
    return
  end

  -- Find the name child (which is a string)
  for child in node:iter_children() do
    if child:type() == "string" then
      local text = vim.treesitter.get_node_text(child, bufnr)
      -- Remove the quotes from the string literal
      return text:gsub('^"(.*)"$', '%1')
    end
  end

  return nil
end

---@param bufnr integer
---@return string[]
function M.get_test_names(bufnr)
  local root = get_root_node(bufnr)
  if not root then
    return {}
  end

  local query = vim.treesitter.query.parse("zig", M.query_test_name)
  local out = {}

  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "test_name" then
      local text = vim.treesitter.get_node_text(node, bufnr)
      -- Remove the quotes from the string literal
      local test_name = text:gsub('^"(.*)"$', '%1')
      table.insert(out, test_name)
    end
  end

  return out
end

---@param bufnr number
---@param cursor_pos integer[]
---@return string[]
function M.get_nearest_test_names(bufnr, cursor_pos)
  local current_test_name = M.get_current_test_name(bufnr, cursor_pos)

  if current_test_name then
    return { current_test_name }
  end

  -- If cursor is not inside a test, don't return all tests
  -- as that would run the wrong test (only first one gets run)
  return {}
end

---@param bufnr number
---@param name string
---@return integer?
function M.get_test_def_line_no(bufnr, name)
  local find_test_by_name_query = string.format(M.query_test_def_line_no, name)

  local root = get_root_node(bufnr)
  if not root then
    return
  end

  local query = vim.treesitter.query.parse("zig", find_test_by_name_query)

  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "test_name" then
      -- Get the parent TestDecl node to get its line number
      local test_node = node:parent()
      if test_node then
        local row, _, _ = test_node:start()
        return row
      end
    end
  end

  return nil
end

return M
