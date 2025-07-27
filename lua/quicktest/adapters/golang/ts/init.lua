-- taken from https://github.com/yanskun/gotests.nvim

local M = {
  query_tbl_testcase_name = [[ ( literal_value (
      literal_element (
        literal_value .(
          keyed_element
            (literal_element (identifier))
            (literal_element (interpreted_string_literal) @test.name)
         )
       ) @test.block
    ))
  ]],

  query_func_name = [[(function_declaration name: (identifier) @func_name)]],

  query_func_def_line_no = [[(
    function_declaration name: (identifier) @func_name
    (#eq? @func_name "%s")
  )]],

  query_sub_testcase_name = [[ (call_expression
    (selector_expression
      (field_identifier) @method.name)
    (argument_list
      (interpreted_string_literal) @tc.name
      (func_literal) )
    (#eq? @method.name "Run")
  ) @tc.run ]],

  -- Table-driven test queries from neotest
  test_function = [[
    ;; query for test function
    (
      (function_declaration
        name: (identifier) @test.name
      ) (#match? @test.name "^(Test|Example)") (#not-match? @test.name "^TestMain$")
    ) @test.definition

    ; query for subtest, like t.Run()
    (call_expression
      function: (selector_expression
        operand: (identifier) @test.operand (#match? @test.operand "^[t]$")
        field: (field_identifier) @test.method) (#match? @test.method "^Run$"
      )
      arguments: (argument_list . (interpreted_string_literal) @test.name)
    ) @test.definition
  ]],

  table_tests_list = [[
    ;; query for list table tests
    (block
      (short_var_declaration
        left: (expression_list
          (identifier) @test.cases
        )
        right: (expression_list
          (composite_literal
            (literal_value
              (literal_element
                (literal_value
                  (keyed_element
                    (literal_element
                      (identifier) @test.field.name
                    )
                    (literal_element
                      (interpreted_string_literal) @test.name
                    )
                  )
                )
              ) @test.definition
            )
          )
        )
      )
      (for_statement
        (range_clause
          left: (expression_list
            (identifier) @test.case
          )
          right: (identifier) @test.cases1 (#eq? @test.cases @test.cases1)
        )
        body: (block
          (expression_statement
            (call_expression
              function: (selector_expression
                operand: (identifier) @test.operand (#match? @test.operand "^[t]$")
                field: (field_identifier) @test.method (#match? @test.method "^Run$")
              )
              arguments: (argument_list
                (selector_expression
                  operand: (identifier) @test.case1 (#eq? @test.case @test.case1)
                  field: (field_identifier) @test.field.name1 (#eq? @test.field.name @test.field.name1)
                )
              )
            )
          )
        )
      )
    )
  ]],

  table_tests_loop = [[
    ;; query for list table tests (wrapped in loop)
    (for_statement
      (range_clause
        left: (expression_list
          (identifier)
          (identifier) @test.case
        )
        right: (composite_literal
          type: (slice_type
            element: (struct_type
              (field_declaration_list
                (field_declaration
                  name: (field_identifier)
                  type: (type_identifier)
                )
              )
            )
          )
          body: (literal_value
            (literal_element
              (literal_value
                (keyed_element
                  (literal_element
                    (identifier)
                  )  @test.field.name
                  (literal_element
                    (interpreted_string_literal) @test.name
                  )
                )
              ) @test.definition
            )
          )
        )
      )
      body: (block
        (expression_statement
          (call_expression
            function: (selector_expression
              operand: (identifier)
              field: (field_identifier)
            )
            arguments: (argument_list
              (selector_expression
                operand: (identifier)
                field: (field_identifier) @test.field.name1
              ) (#eq? @test.field.name @test.field.name1)
            )
          )
        )
      )
    )
  ]],

  table_tests_unkeyed = [[
    ;; query for table tests with inline structs (not keyed)
    (block
      (short_var_declaration
        left: (expression_list (identifier) @test.cases
        )
        right: (expression_list
          (composite_literal
            body: (literal_value
              (literal_element
                (literal_value
                  (literal_element
                    (interpreted_string_literal) @test.name
                  )
                  (literal_element)
                ) @test.definition
              )
            )
          )
        )
      )
      (for_statement
        (range_clause
          left: (expression_list
            (
              (identifier) @test.key.name
            )
            (
              (identifier) @test.case
            )
          )
          right: (identifier) @test.cases1 (#eq? @test.cases @test.cases1)
        )
        body: (block
          (expression_statement
            (call_expression
              function: (selector_expression
                operand: (identifier) @test.operand (#match? @test.operand "^[t]$")
                field: (field_identifier) @test.method (#match? @test.method "^Run$")
              )
              arguments: (argument_list
                (selector_expression
                  operand: (identifier) @test.case1 (#eq? @test.case @test.case1)
                )
              )
            )
          )
        )
      )
    )
  ]],

  table_tests_loop_unkeyed = [[
    ;; query for table tests with inline structs (not keyed, wrapped in loop)
    (for_statement
      (range_clause
        left: (expression_list
          (identifier)
          (identifier) @test.case
        )
        right: (composite_literal
          type: (slice_type
            element: (struct_type
              (field_declaration_list
                (field_declaration
                  name: (field_identifier) @test.field.name
                  type: (type_identifier) @field.type (#eq? @field.type "string")
                )
              )
            )
          )
          body: (literal_value
            (literal_element
              (literal_value
                (literal_element
                  (interpreted_string_literal) @test.name
                )
                (literal_element)
              ) @test.definition
            )
          )
        )
      )
      body: (block
        (expression_statement
          (call_expression
            function: (selector_expression
              operand: (identifier) @test.operand (#match? @test.operand "^[t]$")
              field: (field_identifier) @test.method (#match? @test.method "^Run$")
            )
            arguments: (argument_list
              (selector_expression
                operand: (identifier) @test.case1 (#eq? @test.case @test.case1)
                field: (field_identifier) @test.field.name1 (#eq? @test.field.name @test.field.name1)
              )
            )
          )
        )
      )
    )
  ]],

  table_tests_inline = [[
    ;; query for inline table tests (range over slice literal)
    (for_statement
      (range_clause
        left: (expression_list
          (identifier)
          (identifier) @test.case
        )
        right: (composite_literal
          type: (slice_type
            element: (type_identifier)
          )
          body: (literal_value
            (literal_element
              (literal_value
                (keyed_element
                  (literal_element
                    (identifier) @test.field.name
                  )
                  (literal_element
                    (interpreted_string_literal) @test.name
                  )
                )
              ) @test.definition
            )
          )
        )
      )
      body: (block
        (expression_statement
          (call_expression
            function: (selector_expression
              operand: (identifier) @test.operand (#match? @test.operand "^[t]$")
              field: (field_identifier) @test.method (#match? @test.method "^Run$")
            )
            arguments: (argument_list
              (selector_expression
                operand: (identifier) @test.case1 (#eq? @test.case @test.case1)
                field: (field_identifier) @test.field.name1 (#eq? @test.field.name @test.field.name1)
              )
            )
          )
        )
      )
    )
  ]],

  -- Map-based table tests where test name is the map key
  table_tests_map_key = [[
    ;; query for map-based table tests with string keys
    (for_statement
      (range_clause
        left: (expression_list
          (identifier) @test.key.name
          (identifier) @test.case
        )
        right: (composite_literal
          type: (map_type
            key: (type_identifier) @map.key.type
            value: (type_identifier)
          ) (#eq? @map.key.type "string")
          body: (literal_value
            (keyed_element
              (literal_element
                (interpreted_string_literal) @test.map.key
              )
              (literal_element
                (literal_value) @test.definition
              )
            ) @test.map.element
          )
        )
      )
      body: (block
        (expression_statement
          (call_expression
            function: (selector_expression
              operand: (identifier) @test.operand (#match? @test.operand "^[t]$")
              field: (field_identifier) @test.method (#match? @test.method "^Run$")
            )
            arguments: (argument_list
              (identifier) @test.key.name1 (#eq? @test.key.name @test.key.name1)
            )
          )
        )
      )
    )
  ]],

  -- Map-based table tests where test name is a struct field (like tt.name)
  table_tests_map_field = [[
    ;; query for map-based table tests using struct field as test name
    (for_statement
      (range_clause
        left: (expression_list
          (identifier) @test.key.name
          (identifier) @test.case
        )
        right: (composite_literal
          type: (map_type
            key: (type_identifier) @map.key.type
            value: (type_identifier)
          ) (#eq? @map.key.type "string")
          body: (literal_value
            (keyed_element
              (literal_element
                (interpreted_string_literal) @test.map.key
              )
              (literal_element
                (literal_value
                  (keyed_element
                    (literal_element
                      (identifier) @test.field.name
                    )
                    (literal_element
                      (interpreted_string_literal) @test.struct.name
                    )
                  )
                ) @test.definition
              )
            ) @test.map.field.element
          )
        )
      )
      body: (block
        (expression_statement
          (call_expression
            function: (selector_expression
              operand: (identifier) @test.operand (#match? @test.operand "^[t]$")
              field: (field_identifier) @test.method (#match? @test.method "^Run$")
            )
            arguments: (argument_list
              (selector_expression
                operand: (identifier) @test.case1 (#eq? @test.case @test.case1)
                field: (field_identifier) @test.field.name1 (#eq? @test.field.name @test.field.name1)
              )
            )
          )
        )
      )
    )
  ]],
}

---@param bufnr integer
---@return TSNode?
local function get_root_node(bufnr)
  local parser = vim.treesitter.get_parser(bufnr, "go")
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
function M.get_current_func_name(bufnr, cursor_pos)
  local node = vim.treesitter.get_node({ bufnr = bufnr, pos = cursor_pos })
  if not node then
    return
  end

  while node do
    if node:type() == "function_declaration" then
      break
    end

    node = node:parent()
  end

  if not node then
    return
  end

  return vim.treesitter.get_node_text(node:child(1), bufnr)
end

---@param bufnr integer
---@return string[]
function M.get_func_names(bufnr)
  local root = get_root_node(bufnr)
  if not root then
    return {}
  end

  local query = vim.treesitter.query.parse("go", M.query_func_name)
  local out = {}

  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "func_name" then
      table.insert(out, vim.treesitter.get_node_text(node, bufnr))
    end
  end

  return out
end

---@param bufnr number
---@param cursor_pos integer[]
---@return string[]
function M.get_nearest_func_names(bufnr, cursor_pos)
  local current_func_name = M.get_current_func_name(bufnr, cursor_pos)
  local func_names = { current_func_name }

  if not current_func_name then
    func_names = M.get_func_names(bufnr)
  end

  func_names = vim.tbl_filter(function(v)
    return vim.startswith(v, "Test")
  end, func_names)

  if #func_names == 0 then
    return {}
  end

  return func_names
end

---@param bufnr number
---@param name string
---@return integer?
function M.get_func_def_line_no(bufnr, name)
  local find_func_by_name_query = string.format(M.query_func_def_line_no, name)

  local root = get_root_node(bufnr)
  if not root then
    return
  end

  local query = vim.treesitter.query.parse("go", find_func_by_name_query)

  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == "func_name" then
      local row, _, _ = node:start()

      return row
    end
  end
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return string?
function M.get_sub_testcase_name(bufnr, cursor_pos)
  local root = get_root_node(bufnr)
  if not root then
    return
  end

  local query = vim.treesitter.query.parse("go", M.query_sub_testcase_name)
  local is_inside_test = false
  local curr_row, _ = unpack(cursor_pos)

  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local name = query.captures[id]
    -- tc_run is the first capture of a match, so we can use it to check if we are inside a test
    if name == "tc.run" then
      local start_row, _, end_row, _ = node:range()

      is_inside_test = curr_row >= start_row and curr_row <= end_row
    elseif name == "tc.name" and is_inside_test then
      return vim.treesitter.get_node_text(node, bufnr)
    end
  end

  return nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return string?
function M.get_table_test_name(bufnr, cursor_pos)
  local root = get_root_node(bufnr)
  if not root then
    return
  end

  local all_queries = M.table_tests_list
    .. M.table_tests_loop
    .. M.table_tests_unkeyed
    .. M.table_tests_loop_unkeyed
    .. M.table_tests_inline
    .. M.table_tests_map_key
    .. M.table_tests_map_field
  local query = vim.treesitter.query.parse("go", all_queries)
  local curr_row, _ = unpack(cursor_pos)
  -- from 1-based to 0-based indexing
  curr_row = curr_row - 1

  local test_definitions = {}
  local test_names = {}
  local map_keys = {}
  local map_elements = {}
  local map_field_elements = {}
  local struct_names = {}

  -- collect all the tests definitions and their names
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local name = query.captures[id]
    if name == "test.definition" then
      local start_row, _, end_row, _ = node:range()
      table.insert(test_definitions, {
        node = node,
        start_row = start_row,
        end_row = end_row,
      })
    elseif name == "test.name" then
      local test_name = vim.treesitter.get_node_text(node, bufnr)
      local start_row, _, end_row, _ = node:range()
      table.insert(test_names, {
        name = test_name,
        start_row = start_row,
        end_row = end_row,
        type = "struct_field",
      })
    elseif name == "test.map.key" then
      local test_name = vim.treesitter.get_node_text(node, bufnr)
      local start_row, _, end_row, _ = node:range()
      table.insert(map_keys, {
        name = test_name,
        start_row = start_row,
        end_row = end_row,
        type = "map_key",
      })
    elseif name == "test.map.element" then
      local start_row, _, end_row, _ = node:range()
      table.insert(map_elements, {
        node = node,
        start_row = start_row,
        end_row = end_row,
      })
    elseif name == "test.map.field.element" then
      local start_row, _, end_row, _ = node:range()
      table.insert(map_field_elements, {
        node = node,
        start_row = start_row,
        end_row = end_row,
      })
    elseif name == "test.struct.name" then
      local test_name = vim.treesitter.get_node_text(node, bufnr)
      local start_row, _, end_row, _ = node:range()
      table.insert(struct_names, {
        name = test_name,
        start_row = start_row,
        end_row = end_row,
        type = "struct_name",
      })
    end
  end

  -- combine all possible options
  local all_test_names = {}
  for _, map_key in ipairs(map_keys) do
    table.insert(all_test_names, map_key)
  end
  for _, test_name in ipairs(test_names) do
    table.insert(all_test_names, test_name)
  end
  for _, struct_name in ipairs(struct_names) do
    table.insert(all_test_names, struct_name)
  end

  -- check if we're in a map-based test with struct field as test name
  for _, map_field_element in ipairs(map_field_elements) do
    if curr_row >= map_field_element.start_row and curr_row <= map_field_element.end_row then
      -- find the struct name within this map field element
      for _, struct_name in ipairs(struct_names) do
        if struct_name.start_row >= map_field_element.start_row and struct_name.end_row <= map_field_element.end_row then
          return struct_name.name
        end
      end
    end
  end

  -- check if we're in a map-based test with map key as test name
  local is_in_map_context = false
  for _, map_element in ipairs(map_elements) do
    if curr_row >= map_element.start_row and curr_row <= map_element.end_row then
      is_in_map_context = true
      -- get the map test key
      for _, map_key in ipairs(map_keys) do
        if map_key.start_row >= map_element.start_row and map_key.end_row <= map_element.end_row then
          return map_key.name
        end
      end
    end
  end

  -- If in map context, don't check struct name fields (they're just data)
  if is_in_map_context then
    return nil
  end

  -- Direct match on test names (for non-map contexts)
  for _, test_name in ipairs(all_test_names) do
    if curr_row >= test_name.start_row and curr_row <= test_name.end_row then
      return test_name.name
    end
  end

  -- Check if cursor is within any test definition (for traditional table tests)
  for _, test_def in ipairs(test_definitions) do
    if curr_row >= test_def.start_row and curr_row <= test_def.end_row then
      -- Find struct name fields (for traditional table tests only)
      for _, test_name in ipairs(test_names) do
        if test_name.start_row >= test_def.start_row and test_name.end_row <= test_def.end_row then
          return test_name.name
        end
      end
    end
  end

  return nil
end

---@param bufnr integer
---@return table<string, {row: integer, col: integer}>
function M.get_all_table_tests(bufnr)
  local root = get_root_node(bufnr)
  if not root then
    return {}
  end

  local all_queries = M.table_tests_list
    .. M.table_tests_loop
    .. M.table_tests_unkeyed
    .. M.table_tests_loop_unkeyed
    .. M.table_tests_inline
    .. M.table_tests_map_key
    .. M.table_tests_map_field
  local query = vim.treesitter.query.parse("go", all_queries)
  local tests = {}

  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local name = query.captures[id]
    if name == "test.name" then
      local test_name = vim.treesitter.get_node_text(node, bufnr)
      -- Remove quotes from string literal
      test_name = test_name:gsub('^"(.*)"$', "%1")
      local row, col = node:start()
      tests[test_name] = { row = row, col = col }
    end
  end

  return tests
end

return M
