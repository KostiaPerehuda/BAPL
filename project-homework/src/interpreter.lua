local lpeg = require "lpeg"
local pt = require "pt".pt

------------------------------------------------------- Grammar --------------------------------------------------------

------------------------------------ Debug -------------------------------------

local function I(message)
    return lpeg.P(function() print(message); return true end)
end

local longest_match = 0

local longest_match_tracker = lpeg.P(function(_,position)
    longest_match = math.max(longest_match, position)
    return true
end)

------------------------------ AST Node Factories ------------------------------

--[=[
local function node(tag, ...)
    local labels = table.pack(...)
    local params = table.concat(labels, ", ")
    local fields = {}
    for i, v in ipairs(labels) do fields[i] = v.." = "..v end 
    fields = table.concat(fields, ", ")
    local code  = string.format("return function(%s) return {tag = '%s', %s} end", params, tag, fields)
    return assert(load(code))()
end
--]=]

---[=[
local function node(tag, ...)
    local labels = table.pack(...)
    return function(...)
        local params = table.pack(...)
        local node = { tag = tag }
        for i = 1, #labels do
            node[labels[i]] = params[i]
        end
        return node
    end
end
--]=]

-------------------------------- Basic Patterns --------------------------------
local digit = lpeg.R("09")
local hex_digit = lpeg.R("09", "af", "AF")

local alpha_char = lpeg.R("AZ", "az")
local alpha_numeric_char = alpha_char + digit

local alpha_char_or_underscore = alpha_char + "_"
local alpha_numeric_char_or_underscore = alpha_numeric_char + "_"

local whitespace = lpeg.S(" \t\r\n")

----------------------------------- Comments -----------------------------------
local line_comment = "#" * (lpeg.P(1) - lpeg.S("\r\n"))^0
local block_comment = "#{" * (lpeg.P(1) - "#}")^0 * "#}"
local comment = block_comment + line_comment

------------------------------------ Spaces ------------------------------------
local space = (whitespace + comment)^0 * longest_match_tracker

--------------------------- Tokens and Reserved Words --------------------------

local function T(t)
    return t * space
end

local reserved_words = {"return", "if", "elseif", "else", "while", "and", "or", "new", "function", "var"}

local reserved = lpeg.P(false)
for i = 1, #reserved_words do
    reserved = reserved + reserved_words[i]
end
reserved = reserved * -alpha_numeric_char_or_underscore

local function RW(word)
    assert(reserved:match(word),
        "'"..word.."' cannot be used as a reserved word! "
        .."You must first insert it into the 'reserved_words' list!")
    return word * -alpha_numeric_char_or_underscore * space
end

------------------------------------ Number ------------------------------------
local function to_number_node(number)
    return { tag = "number", number_value = tonumber(number) }
end

local e_notation_suffix = (lpeg.S("eE") * lpeg.P"-"^-1 * digit^1)^-1
local dec_number_body = ((digit^1 * lpeg.P"."^-1 * digit^0) + ("." * digit^1)) * e_notation_suffix

local hex_number_prefix = "0" * lpeg.S("xX")
local hex_number_body = (hex_digit^1 * lpeg.P"."^-1 * hex_digit^0) + ("." * hex_digit^1)

local dec_number = -hex_number_prefix * dec_number_body
local hex_number =  hex_number_prefix * hex_number_body

local number = lpeg.C(dec_number + hex_number) / to_number_node * space

---------------------------------- Identifier ----------------------------------
local exclude_reserved_words = lpeg.P(function(input, position)
    for _, reserved_word in pairs(reserved_words) do
        if input:sub(1, position-1):sub(-#reserved_word) == reserved_word then
           return false
        end
    end
    return true
end)

local identifier = T(lpeg.C(alpha_char_or_underscore * alpha_numeric_char_or_underscore^0) * exclude_reserved_words)

----------------------------------- Variable -----------------------------------
local function to_variable_node(variable_name)
    return { tag = "variable", variable_name = variable_name }
end

local variable = identifier / to_variable_node

---------------------------------- Expression ----------------------------------

local function to_binop_node(left_operand, operator, right_operand)
    return { tag = "binop", left_operand = left_operand, operator = operator, right_operand = right_operand }
end

local function fold_left_into_binop_tree(list)
    local tree = list[1]
    for i = 2, #list, 2 do tree = to_binop_node(tree, list[i], list[i + 1]) end
    return tree
end

local function fold_right_into_binop_tree(list)
    local tree = list[#list]
    for i = #list - 1, 2, -2 do tree = to_binop_node(list[i - 1], list[i], tree) end
    return tree
end

local function apply_unary_operator(operator, expression)
    return { tag = "unary_operator", operator = operator, operand = expression }
end

local function to_logical_operator_node(left_operand, operator, right_operand)
    return { tag = "logical_operator", left_operand = left_operand, operator = operator, right_operand = right_operand }
end

local function fold_left_into_logical(operator)
    return function(list)
        local tree = list[1]
        for i = 2, #list do tree = to_logical_operator_node(tree, operator, list[i]) end
        return tree
    end
end

local function fold_left_into_indexed_node(list)
    local to_indexed_node = node("indexed", "variable", "index")
    local tree = list[1]
    for i = 2, #list do tree = to_indexed_node(tree, list[i]) end
    return tree
end

local exponential_operator    = T(lpeg.C(lpeg.S("^")))
local negation_operator       = T(lpeg.C(lpeg.S("-!")))
local additive_operator       = T(lpeg.C(lpeg.S("+-")))
local multiplicative_operator = T(lpeg.C(lpeg.S("*/%")))

local comparison_operator = lpeg.C(lpeg.P("==") + "!=" + "<=" + ">=" + "<" +">") * space

local expression  = lpeg.V"expression"

local  logical_or = lpeg.V"logical_or"
local logical_and = lpeg.V"logical_and"
local  comparison = lpeg.V"comparison"
local     sum     = lpeg.V"sum"
local     term    = lpeg.V"term"
local   negation  = lpeg.V"negation"
local   exponent  = lpeg.V"exponent"
local     atom    = lpeg.V"atom"
local indexed_var = lpeg.V"indexed_var"
local  new_array  = lpeg.V"new_array"
local function_call = lpeg.V"function_call"

local expression = lpeg.P{"expression", expression = logical_or,
     logical_or = lpeg.Ct(logical_and * (RW"or" * logical_and)^0) / fold_left_into_logical("or"),
    logical_and = lpeg.Ct( comparison * (RW"and" * comparison)^0) / fold_left_into_logical("and"),
     comparison = lpeg.Ct(  sum    * (  comparison_operator   *   sum   )^0) / fold_left_into_binop_tree,
        sum     = lpeg.Ct(  term   * (   additive_operator    *   term  )^0) / fold_left_into_binop_tree,
        term    = lpeg.Ct(negation * (multiplicative_operator * negation)^0) / fold_left_into_binop_tree,
      negation  = (negation_operator * negation / apply_unary_operator) + exponent,
      exponent  = lpeg.Ct(  atom   * (  exponential_operator  *   atom  )^0) / fold_right_into_binop_tree,
        atom    = (T"(" * expression * T")") + number + new_array + function_call + indexed_var, 
     new_array  = RW"new" * lpeg.Ct((T"[" * expression * T"]")^1) / node("new_array", "array_size"),
    function_call = identifier * T"(" * T")" / node("call", "call_site_name"),
    indexed_var = lpeg.Ct(variable * (T"[" * expression * T"]")^0) / fold_left_into_indexed_node,
}

-------------------------------- Local Variables -------------------------------
local local_var = RW"var" * identifier * (T"=" * expression)^-1 / node("local_variable", "name", "initial_value")

---------------------------------- Assignment ----------------------------------
local assignment_target = lpeg.Ct(variable * (T"[" * expression * T"]")^0) / fold_left_into_indexed_node
local assignment = assignment_target * T"=" * expression / node("assignment", "target", "expression")

------------------------------- Return Statement -------------------------------
local return_statement = RW"return" * expression / node("return", "expression")

------------------------------- Print Statement --------------------------------
local print_statement = T"@" * expression / node("print", "expression")

----------------------------- Sequences and Blocks -----------------------------
local skip_node = node("skip")
local sequence_node = node("sequence", "first", "second")

local function fold_right_to_sequence_node(statements)
    if #statements == 0 then return skip_node() end

    local node = statements[#statements]
    for i = #statements - 1, 1, -1 do
        node = sequence_node(statements[i], node)
    end
    return node
end

local if_node = node("if", "condition", "if_branch", "else_branch")

local function fold_right_to_if_node(list)
    local last_if_node_index = #list - (#list % 2) - 1
    local node = if_node(list[last_if_node_index], list[last_if_node_index + 1], list[last_if_node_index + 2])
    for i = last_if_node_index - 1, 1, -2 do node = if_node(list[i - 1], list[i], node) end
    return node
end

local delimiter = T";"^1

local sequence  = lpeg.V"sequence"
local block     = lpeg.V"block"
local statement    = lpeg.V"statement"
local if_statement = lpeg.V"if_statement"
local while_statement = lpeg.V"while_statement"
local function_header = lpeg.V"function_header"
local function_decl = lpeg.V"function_decl"
local function_def = lpeg.V"function_def"
local call_statement = lpeg.V"call_statement"

-- TODO: a "block" is a purely syntactic feature for now, it has no meaning,
--       for the compiler.
--       The parser just drops the block-start and block-end anchors.
--       Will most probably be changed in the future when we will implement
--       local variables and stack frames.
local program = lpeg.P{"functions",

    functions = lpeg.Ct((function_decl + function_def)^0),

    function_header = RW"function" * identifier * T"(" * T")",
    function_decl = (function_header * T";") / node("function", "name"),
    function_def = (function_header * block) / node("function", "name", "body"),

    sequence = lpeg.Ct((statement * (delimiter * statement)^0)^-1) / fold_right_to_sequence_node * delimiter^-1,
    block    = T"{" * sequence * T"}" / node("block", "body"),
    
    statement = block
                + assignment
                + call_statement
                + return_statement
                + print_statement
                + if_statement
                + while_statement
                + local_var,

    if_statement = lpeg.Ct(
        (RW"if" * expression * block)
        * (RW"elseif" * expression * block)^0
        * (RW"else" * block)^-1
        ) / fold_right_to_if_node,

    while_statement = RW"while" * expression * block / node("while", "condition", "loop_body"),

    call_statement = identifier * T"(" * T")" / node("call", "call_site_name"),
}
--------------------------------------------------------------------------------

local grammar = space * program * -1

-------------------------------------------------------- Parser --------------------------------------------------------

local function get_line_and_column(input, position)
    input = input .. "\n"
    line_number = 0

    for line in input:gmatch(".-\n") do
        line_number = line_number + 1
        position = position - line:len()
        if position <= 0 then
            trimmed_line = (line:sub(-2, -2) == "\r") and line:sub(1, -3) or line:sub(1, -2)
            return line_number, position + line:len(), trimmed_line
        end
    end
end

local function syntax_error(input, longest_match)
    -- longest match == next char to consume
    line_num, col_num, line = get_line_and_column(input, longest_match)
    io.stderr:write(string.format("Syntax Error at Line %d, Col %d! ('%s')\n", line_num, col_num, line))
    io.stderr:write(string.format("Unexpected Symbol '%s' after '%s'\n",
                                        line:sub(col_num, col_num), line:sub(1, col_num-1)))
    os.exit(1)
  end

local function parse(input)
    local ast = grammar:match(input)
    if not ast then syntax_error(input, longest_match) end
    return ast
end

------------------------------------------------------- Compiler -------------------------------------------------------

local Compiler = { functions = {}, globals = {}, nglobals = 0, locals = {} }

function Compiler:add_opcode(opcode)
    local code = self.code
    code[#code + 1] = opcode
end

local opcode_from_binary_operator = {
    ["=="] = "eq", ["!="] = "neq", ["<="] = "lte", [">="] = "gte", ["<"] = "lt", [">"] = "gt",
    ["+"] = "add", ["-"] = "sub",
    ["*"] = "mul", ["/"] = "div", ["%"] = "mod",
    ["^"] = "exp",
}

local function get_opcode_from_binary_operator(operator)
    return opcode_from_binary_operator[operator] or error("invalid tree")
end

local opcode_from_unary_operator = {
    ["-"] = "negate", ["!"] = "not",
}

local function get_opcode_from_unary_operator(operator)
    return opcode_from_unary_operator[operator] or error("invalid tree")
end

local jump_opcode_from_logical_operator = {
    ["and"] = "jump_if_zero_or_pop", ["or"] = "jump_if_not_zero_or_pop"
}

local function get_jump_opcode_from_logical_operator(operator)
    return jump_opcode_from_logical_operator[operator] or error("invalid tree")
end

function Compiler:global_variable_index_from_name(variable_name)
    local num = self.globals[variable_name]
    if not num then
        assert(not self.functions[variable_name],
                "Compiler Error: Cannot use '" .. variable_name .. "' as a variable, "
                .. "because a function with the same name is already defined!")
        num = self.nglobals + 1
        self.nglobals = num
        self.globals[variable_name] = num
    end
    return num
end

function Compiler:assert_variable_is_defined(variable_name)
    assert(self.globals[variable_name], "Varible '" .. variable_name .. "' is referenced before being defined!")
end

function Compiler:find_local(name)
    local locals = self.locals
    for i = #locals, 1, -1 do
        if name == locals[i] then
            return i
        end
    end
    return nil
end

function Compiler:current_position()
    return #self.code
end

function Compiler:generate_jump(jump)
    self:add_opcode(jump or "jump")
    self:add_opcode(0)
    return self:current_position()
end

function Compiler:generate_jump_to(position, jump_factory)
    self:point_jump_to((jump_factory or self.generate_jump)(self), position)
end

function Compiler:generate_jump_if_zero()
    return self:generate_jump("jump_if_zero")
end

function Compiler:point_jump_to(jump, position)
    self.code[jump] = position - jump
end

function Compiler:point_jump_to_here(jump)
    self:point_jump_to(jump, self:current_position())
end

function Compiler:generate_code_from_call(call_node)
    local call_site = self.functions[call_node.call_site_name]
    if not call_site then error("Compilation Error: undefined function '" .. call_node.call_site_name .. "'!") end
    self:add_opcode("call")
    self:add_opcode(call_site)
end

function Compiler:generate_code_from_expression(expression)
    if expression.tag == "number" then
        self:add_opcode("push")
        self:add_opcode(expression.number_value)
    elseif expression.tag == "call" then
        self:generate_code_from_call(expression)
    elseif expression.tag == "variable" then
        -- UPDATE: with introduction of the functions and branches, this check has to live at run-time only
        -- self:assert_variable_is_defined(expression.variable_name)
        local local_index = self:find_local(expression.variable_name)
        if local_index then
            self:add_opcode("load_local")
            self:add_opcode(local_index)
        else
            self:add_opcode("load")
            self:add_opcode(self:global_variable_index_from_name(expression.variable_name))
        end
    elseif expression.tag == "indexed" then
        self:generate_code_from_expression(expression.variable)
        self:generate_code_from_expression(expression.index)
        self:add_opcode("array_load")
    elseif expression.tag == "new_array" then
        for i = 1, #expression.array_size do
            self:generate_code_from_expression(expression.array_size[i])
        end
        self:add_opcode("new_array")
        self:add_opcode(#expression.array_size)
    elseif expression.tag == "binop" then
        self:generate_code_from_expression(expression.left_operand)
        self:generate_code_from_expression(expression.right_operand)
        self:add_opcode(get_opcode_from_binary_operator(expression.operator))
    elseif expression.tag == "logical_operator" then
        self:generate_code_from_expression(expression.left_operand)
        local jump = self:generate_jump(get_jump_opcode_from_logical_operator(expression.operator))
        self:generate_code_from_expression(expression.right_operand)
        self:point_jump_to_here(jump)
    elseif expression.tag == "unary_operator" then
        self:generate_code_from_expression(expression.operand)
        self:add_opcode(get_opcode_from_unary_operator(expression.operator))
    else
        error("invalid expression tree: " .. pt(expression))
    end
end

function Compiler:verify_no_local_variable_redeclaration_in_current_block(old_level)
    local locals = self.locals
    for i = old_level, #locals do
        for j = i + 1, #locals do
            if locals[i] == locals[j] then
                error("Compilation Error: Local variable '" .. locals[i]
                        .. "' has been declared more than once in the same block!")
            end
        end
    end
end

function Compiler:generate_code_from_block(block)
    local old_level = #self.locals
    self:generate_code_from_statement(block.body)
    local diff = #self.locals - old_level
    if diff > 0 then
        self:verify_no_local_variable_redeclaration_in_current_block(old_level)
        for i = 1, diff do
            table.remove(self.locals)
        end
        self:add_opcode("pop")
        self:add_opcode(diff)
    end
end

function Compiler:generate_code_from_assignment(assignment)
    self:generate_code_from_expression(assignment.expression)
    if assignment.target.tag == "variable" then
        local local_index = self:find_local(assignment.target.variable_name)
        if local_index then
            self:add_opcode("store_local")
            self:add_opcode(local_index)
        else
            self:add_opcode("store")
            self:add_opcode(self:global_variable_index_from_name(assignment.target.variable_name))
        end
    elseif assignment.target.tag == "indexed" then
        self:generate_code_from_expression(assignment.target.variable)
        self:generate_code_from_expression(assignment.target.index)
        self:add_opcode("array_store")
    else
        error("invalid tree for assignment target")
    end
end

function Compiler:generate_code_from_statement(statement)
    if statement.tag == "assignment" then
        self:generate_code_from_assignment(statement)
    elseif statement.tag == "local_variable" then
        self:generate_code_from_expression(statement.initial_value or to_number_node(0))
        self.locals[#self.locals + 1] = statement.name
    elseif statement.tag == "block" then
        self:generate_code_from_block(statement)
    elseif statement.tag == "call" then
        self:generate_code_from_call(statement)
        self:add_opcode("pop")
        self:add_opcode(1)
    elseif statement.tag == "sequence" then
        self:generate_code_from_statement(statement.first)
        self:generate_code_from_statement(statement.second)
    elseif statement.tag == "if" then
        self:generate_code_from_expression(statement.condition)
        local jump = self:generate_jump_if_zero()
        self:generate_code_from_statement(statement.if_branch)
        if statement.else_branch == nil then
            self:point_jump_to_here(jump)
        else
            local jump2 = self:generate_jump()
            self:point_jump_to_here(jump)
            self:generate_code_from_statement(statement.else_branch)
            self:point_jump_to_here(jump2)
        end
    elseif statement.tag == "while" then
        local loop_start = self:current_position()
        self:generate_code_from_expression(statement.condition)
        local jump = self:generate_jump_if_zero()
        self:generate_code_from_statement(statement.loop_body)
        self:generate_jump_to(loop_start)
        self:point_jump_to_here(jump)
    elseif statement.tag == "return" then
        self:generate_code_from_expression(statement.expression)
        self:add_opcode("ret")
        self:add_opcode(#self.locals)
    elseif statement.tag == "print" then
        self:generate_code_from_expression(statement.expression)
        self:add_opcode("print")
    elseif statement.tag == "skip" then
        --skip
    else
        error("invalid tree")
    end
end

function Compiler:declare_function(function_node)
    
    if self.functions[function_node.name] then return end

    if self.globals[function_node.name] then
        error("Compilation Error: Function '" .. function_node.name .. "' cannot be declared, \
            \rbecause there already exists a global variable with the same name!")
    end
    self.functions[function_node.name] = { name = function_node.name }
end

function Compiler:compile_function(function_node)

    self:declare_function(function_node)
    
    if not function_node.body then return end
    
    if self.functions[function_node.name].code then
        error("Compilation Error: Function '" .. function_node.name .. "' has been defined more than once!")
    end

    local code  = {}
    self.code = code
    self.functions[function_node.name].code = code
    self:generate_code_from_statement(function_node.body)
    self:generate_code_from_statement(node("return", "expression")(to_number_node(0)))
end

local function compile(ast)
    for _, function_node in ipairs(ast) do
        Compiler:declare_function(function_node)
    end
    for _, function_node in ipairs(ast) do
        Compiler:compile_function(function_node)
    end
    for _, call_site in ipairs(Compiler.functions) do
        assert(call_site.code,
                "Compilation Error: function '" .. call_site.name .. "' has been declared but not defined!")
    end
    local main = Compiler.functions["main"]
    if not main then error("No function named 'main'") end
    return main
end

----------------------------------------------------- Interpreter ------------------------------------------------------

local function is_array(value)
    return type(value) == "table" and value.size ~= nil
end

local function value_as_string(value, visited_arrays)
    if not is_array(value) then return tostring(value) end

    local array_prefix = "array["..tostring(value.size).."]: { "
    local array_suffix = " }"
    
    visited_arrays = visited_arrays or {}
    if visited_arrays[value] then return array_prefix .. "..." .. array_suffix end
    visited_arrays[value] = true

    if value.size == 1 then return array_prefix .. value_as_string(value[1], visited_arrays) .. array_suffix end

    local array_as_string = array_prefix
    for i = 1, value.size - 1 do
        array_as_string = array_as_string .. value_as_string(value[i], visited_arrays) .. ", "
    end
    array_as_string = array_as_string .. value_as_string(value[value.size], visited_arrays) .. array_suffix

    return array_as_string
end

local function stack_as_string(stack, stack_top)
    local stack_as_string = "{ Top --> |"
    for i = stack_top, 1, -1 do stack_as_string = stack_as_string .. value_as_string(stack[i]) .. "|" end
    stack_as_string = stack_as_string .. " <-- Bottom }"
    return stack_as_string
end

local function instruction_as_string(code, instruction_pointer)
    local instruction = code[instruction_pointer]
    if instruction == "push" then
        instruction = instruction .. " " .. tostring(code[instruction_pointer + 1])
    elseif instruction == "load" or instruction == "store" then
        instruction = instruction .. " '" .. code[instruction_pointer + 1] .. "'"
    elseif instruction == "call" then
        instruction = instruction .. " '" .. code[instruction_pointer + 1].name .. "'"
    end
    instruction = "{ " .. instruction .. " }"
    return instruction
end

------------------------------------ Logger ------------------------------------

local function log_intrepreter_start(trace_enabled)
    if not trace_enabled then return end
    print("Starting Interpreter...")
end

local function log_intrepreter_state(trace_enabled, cycle, code, pc, stack, stack_top)
    if not trace_enabled then return end
    
    print("Interpreter Cycle: " .. cycle)
    print("\t" .. "PC = " .. tostring(pc))
    print("\t" .. "Stack = " .. stack_as_string(stack, stack_top))
    print("\t" .. "Current Instruction = " .. instruction_as_string(code, pc))
end

local function log_interpreter_exit(trace_enabled, return_value)
    if not trace_enabled then return end
    print("Finished Execution. Returning '" .. value_as_string(return_value) .."'")
end

local function log_function_start(trace_enabled, function_name)
    if not trace_enabled then return end
    print("Calling function '" .. function_name .. "'...")
end

local function log_function_exit(trace_enabled, function_name)
    if not trace_enabled then return end
    print("Returning from function '" .. function_name .."'...")
end

------------------------------------ Runner ------------------------------------

local function verify_array_size(size)
    assert(math.type(size) == "integer" and size >= 1,
        "ArrayCreationError: an array size must be a positive integer, but got '" .. size .. "'!")
end

local function verify_array_type_and_index_bounds(array, index)
    assert(is_array(array),
        "ArrayAccessError: cannot perform array access on a non-array type!")
    assert(math.type(index) == "integer",
        "ArrayAccessError: a non-integer value '".. index .."' cannot be used as an array index!")
    assert(index >= 1 and index <= array.size,
        "ArrayAccessError: index '".. index .. "' is out of bounds of array of size " .. array.size .. "!")
end

local function drop(stack, top, number_of_values)
    for i = top - number_of_values + 1, top do stack[i] = nil end
    return top - number_of_values
end

local function allocate_new_array(sizes, start_at_size)
    local start_at_size = start_at_size or 1
    local size = sizes[start_at_size]
    verify_array_size(size)

    local array = { size = size }
    for i = 1, size do
        array[i] = (start_at_size ~= #sizes)
            and allocate_new_array(sizes, start_at_size + 1) or 0
    end
    return array
end

local function verify_call_site_can_be_executed(call_site)
    assert(call_site.code,
        "Runtime Error: function  '" .. call_site.name .. "' cannot be executed, as it has no associated code!")
end

local function run(call_site, memory, stack, top, trace_enabled, cycle)
    verify_call_site_can_be_executed(call_site)


    trace_enabled = trace_enabled or false
    cycle = (cycle or 0) + 1

    local code = call_site.code
    local base = top
    local pc = 1

    log_function_start(trace_enabled, call_site.name)

    while true do
        log_intrepreter_state(trace_enabled, cycle, code, pc, stack, top)

        local current_instruction = code[pc]

        if current_instruction == "ret" then
            log_function_exit(trace_enabled, call_site.name)

            local n = code[pc + 1]
            stack[top - n] = stack[top]
            top = drop(stack, top, n)

            return top, cycle
        elseif current_instruction == "call" then
            pc = pc + 1
            local call_site = code[pc]
            top, cycle = run(call_site, memory, stack, top, trace_enabled, cycle)
        elseif current_instruction == "print" then
            print(value_as_string(stack[top]))
            top = drop(stack, top, 1)
        elseif current_instruction == "jump" then
            pc = pc + 1
            pc = pc + code[pc]
        elseif current_instruction == "jump_if_zero" then
            pc = pc + 1
            pc = pc + ((stack[top] == 0) and code[pc] or 0)
            top = drop(stack, top, 1)
        elseif current_instruction == "jump_if_zero_or_pop" then
            pc = pc + 1
            if stack[top] == 0 then
                pc = pc + code[pc]
            else
                top = drop(stack, top, 1)
            end
        elseif current_instruction == "jump_if_not_zero_or_pop" then
            pc = pc + 1
            if stack[top] ~= 0 then
                pc = pc + code[pc]
            else
                top = drop(stack, top, 1)
            end
        elseif current_instruction == "push" then
            pc = pc + 1
            top = top + 1
            stack[top] = code[pc]
        elseif current_instruction == "pop" then
            pc = pc + 1
            top = drop(stack, top, code[pc])
        elseif code[pc] == "load_local" then
            pc = pc + 1
            top = top + 1
            stack[top] = stack[base + code[pc]]
        elseif code[pc] == "load" then
            pc = pc + 1
            top = top + 1
            -- TODO: might be useful to throw undefined variable exception here
            --       in case the variable is not present in the memory
            -- UPDATE: now that we handle undefined variables at compile time, this is no longer an issue.
            --      BUT, if we separate out compilation and execution stages later on, we will still need
            --           to verify this at runtime.
            -- UPDATE: with introduction of the functions and branches, this check has to live at run-time only
            stack[top] = memory[code[pc]]
            assert(stack[top] ~= nil, "Runtime Error: Attempt to reference uninitialized variable '" .. code[pc] .. "'!")
        elseif code[pc] == "store_local" then
            pc = pc + 1
            stack[base + code[pc]] = stack[top]
            top = drop(stack, top, 1)
        elseif code[pc] == "store" then
            pc = pc + 1
            memory[code[pc]] = stack[top]
            top = drop(stack, top, 1)
        elseif code[pc] == "new_array" then
            pc = pc + 1
            local number_of_dimensions = code[pc]
            local sizes = table.move(stack, top - number_of_dimensions + 1, top, 1, {})
            top = drop(stack, top, number_of_dimensions - 1)
            stack[top] = allocate_new_array(sizes)
        elseif code[pc] == "array_load" then
            local array = stack[top - 1]
            local index = stack[top]
            verify_array_type_and_index_bounds(array, index)
            stack[top - 1] = array[index]
            top = drop(stack, top, 1)
        elseif code[pc] == "array_store" then
            local value = stack[top - 2]
            local array = stack[top - 1]
            local index = stack[top]
            verify_array_type_and_index_bounds(array, index)
            array[index] = value
            top = drop(stack, top, 3)
        elseif current_instruction == "eq" then
            stack[top - 1] = (stack[top - 1] == stack[top]) and 1 or 0
            top = drop(stack, top, 1)
        elseif current_instruction == "neq" then
            stack[top - 1] = (stack[top - 1] ~= stack[top]) and 1 or 0
            top = drop(stack, top, 1)
        elseif current_instruction == "lte" then
            stack[top - 1] = (stack[top - 1] <= stack[top]) and 1 or 0
            top = drop(stack, top, 1)
        elseif current_instruction == "gte" then
            stack[top - 1] = (stack[top - 1] >= stack[top]) and 1 or 0
            top = drop(stack, top, 1)
        elseif current_instruction == "lt" then
            stack[top - 1] = (stack[top - 1] < stack[top]) and 1 or 0
            top = drop(stack, top, 1)
        elseif current_instruction == "gt" then
            stack[top - 1] = (stack[top - 1] > stack[top]) and 1 or 0
            top = drop(stack, top, 1)
        elseif current_instruction == "not" then
            stack[top] = (stack[top] == 0) and 1 or 0
        elseif current_instruction == "add" then
            stack[top - 1] = stack[top - 1] + stack[top]
            top = drop(stack, top, 1)
        elseif current_instruction == "sub" then
            stack[top - 1] = stack[top - 1] - stack[top]
            top = drop(stack, top, 1)
        elseif current_instruction == "mul" then
            stack[top - 1] = stack[top - 1] * stack[top]
            top = drop(stack, top, 1)
        elseif current_instruction == "div" then
            stack[top - 1] = stack[top - 1] / stack[top]
            top = drop(stack, top, 1)
        elseif current_instruction == "mod" then
            stack[top - 1] = stack[top - 1] % stack[top]
            top = drop(stack, top, 1)
        elseif current_instruction == "exp" then
            stack[top - 1] = stack[top - 1] ^ stack[top]
            top = drop(stack, top, 1)
        elseif current_instruction == "negate" then
            stack[top] = -stack[top]
        else
            error("unknown instruction: '" .. current_instruction .. "'")
        end

        -- can only have numbers or arrays on the stack
        assert(top == 0 or top > 0 and (type(stack[top]) == "number" or type(stack[top]) == "table"))

        pc = pc + 1
        cycle = cycle + 1
    end
end

--------------------------------------------------------- Main ---------------------------------------------------------

local source = io.read("a")

local ast = parse(source)
print("Abstract Syntax Tree:", pt(ast), "\n")

local main_function = compile(ast)
print("Compiled Code:", pt(main_function), "\n")

local trace_enabled = true

local memory = {}
local stack = {}
local stack_top = 0
log_intrepreter_start(trace_enabled)
stack_top = run(main_function, memory, stack, stack_top, trace_enabled)
local result = stack[stack_top]
log_interpreter_exit(trace_enabled, result)

print("Execution Result = " .. tostring(result))
