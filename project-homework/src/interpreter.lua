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
    return load(code)()
end

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

local reserved_words = {"return", "if"}

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

local exponential_operator    = T(lpeg.C(lpeg.S("^")))
local negation_operator       = T(lpeg.C(lpeg.S("-!")))
local additive_operator       = T(lpeg.C(lpeg.S("+-")))
local multiplicative_operator = T(lpeg.C(lpeg.S("*/%")))

local comparison_operator = lpeg.C(lpeg.P("==") + "!=" + "<=" + ">=" + "<" +">") * space

local expression = lpeg.V"expression"
local comparison = lpeg.V"comparison"
local    sum     = lpeg.V"sum"
local    term    = lpeg.V"term"
local  negation  = lpeg.V"negation"
local  exponent  = lpeg.V"exponent"
local    atom    = lpeg.V"atom"

local expression = lpeg.P{"expression", expression = comparison,
    comparison = lpeg.Ct(  sum    * (  comparison_operator   *   sum   )^0) / fold_left_into_binop_tree,
       sum     = lpeg.Ct(  term   * (   additive_operator    *   term  )^0) / fold_left_into_binop_tree,
       term    = lpeg.Ct(negation * (multiplicative_operator * negation)^0) / fold_left_into_binop_tree,
     negation  = (negation_operator * negation / apply_unary_operator) + exponent,
     exponent  = lpeg.Ct(  atom   * (  exponential_operator  *   atom  )^0) / fold_right_into_binop_tree,
       atom    = (T"(" * expression * T")") + number + variable,
}

---------------------------------- Assignment ----------------------------------
local function to_assignment_node(identifier, expression)
    return { tag = "assignment", assignment_target = identifier, expression = expression }
end

local assignment = identifier * T"=" * expression / to_assignment_node

------------------------------- Return Statement -------------------------------
local function to_return_node(expression)
    return { tag = "return", expression = expression }
end

local return_statement = RW"return" * expression / to_return_node

------------------------------- Print Statement --------------------------------
local function to_print_node(expression)
    return { tag = "print", expression = expression }
end

local print_statement = T"@" * expression / to_print_node

----------------------------- Sequences and Blocks -----------------------------
local function skip_node()
    return { tag = "skip" }
end

local function to_sequence_node(first_statement, second_statement)
    return { tag = "sequence", first = first_statement, second = second_statement }
end

local function fold_right_to_sequence_node(statements)
    if #statements == 0 then return skip_node() end

    local node = statements[#statements]
    for i = #statements - 1, 1, -1 do
        node = to_sequence_node(statements[i], node)
    end
    return node
end

local delimiter = T";"^1

local sequence  = lpeg.V"sequence"
local statement = lpeg.V"statement"
local block     = lpeg.V"block"

-- TODO: a "block" is a purely syntactic feature for now, it has no meaning,
--       for the compiler.
--       The parser just drops the block-start and block-end anchors.
--       Will most probably be changed in the future when we will implement
--       local variables and stack frames.
local statements = lpeg.P{"sequence",
    sequence  = lpeg.Ct((statement * (delimiter * statement)^0)^-1) / fold_right_to_sequence_node * delimiter^-1,
    statement = block + assignment + return_statement + print_statement,
    block     = T"{" * sequence * T"}",
}
--------------------------------------------------------------------------------

local grammar = space * statements * -1

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

local Compiler = { code = {}, vars = {}, nvars = 0 }

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

function Compiler:variable_index_from_name(variable_name)
    local num = self.vars[variable_name]
    if not num then
        num = self.nvars + 1
        self.nvars = num
        self.vars[variable_name] = num
    end
    return num
end

function Compiler:assert_variable_is_defined(variable_name)
    assert(self.vars[variable_name], "Varible '" .. variable_name .. "' is referenced before being defined!")
end

function Compiler:generate_code_from_expression(expression)
    if expression.tag == "number" then
        self:add_opcode("push")
        self:add_opcode(expression.number_value)
    elseif expression.tag == "variable" then
        self:assert_variable_is_defined(expression.variable_name)
        self:add_opcode("load")
        self:add_opcode(self:variable_index_from_name(expression.variable_name))
    elseif expression.tag == "binop" then
        self:generate_code_from_expression(expression.left_operand)
        self:generate_code_from_expression(expression.right_operand)
        self:add_opcode(get_opcode_from_binary_operator(expression.operator))
    elseif expression.tag == "unary_operator" then
        self:generate_code_from_expression(expression.operand)
        self:add_opcode(get_opcode_from_unary_operator(expression.operator))
    else
        error("invalid tree")
    end
end

function Compiler:generate_code_from_statement(statement)
    if statement.tag == "assignment" then
        self:generate_code_from_expression(statement.expression)
        self:add_opcode("store")
        self:add_opcode(self:variable_index_from_name(statement.assignment_target))
    elseif statement.tag == "sequence" then
        self:generate_code_from_statement(statement.first)
        self:generate_code_from_statement(statement.second)
    elseif statement.tag == "return" then
        self:generate_code_from_expression(statement.expression)
        self:add_opcode("ret")
    elseif statement.tag == "print" then
        self:generate_code_from_expression(statement.expression)
        self:add_opcode("print")
    elseif statement.tag == "skip" then
        --skip
    else
        error("invalid tree")
    end
end

local function compile(ast)
    Compiler:generate_code_from_statement(ast)
    Compiler:generate_code_from_statement(to_return_node(to_number_node(0)))
    return Compiler.code
end

----------------------------------------------------- Interpreter ------------------------------------------------------

------------------------------------ Logger ------------------------------------

local function stack_as_string(stack, stack_top)
    local stack_as_string = "{ Top --> |"
    for i = stack_top, 1, -1 do stack_as_string = stack_as_string .. tostring(stack[i]) .. "|" end
    stack_as_string = stack_as_string .. " <-- Bottom }"
    return stack_as_string
end

local function instruction_as_string(code, instruction_pointer)
    local instruction = code[instruction_pointer]
    if instruction == "push" then
        instruction = instruction .. " " .. tostring(code[instruction_pointer + 1])
    elseif instruction == "load" or instruction == "store" then
        instruction = instruction .. " '" .. code[instruction_pointer + 1] .. "'"
    end
    instruction = "{ " .. instruction .. " }"
    return instruction
end

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
    print("Finished Execution. Returning '" .. return_value .."'")
end

------------------------------------ Runner ------------------------------------

local function run(code, memory, stack, trace_enabled)
    local cycle = 1
    local pc = 1
    local top = 0

    log_intrepreter_start(trace_enabled)

    while true do
        log_intrepreter_state(trace_enabled, cycle, code, pc, stack, top)

        local current_instruction = code[pc]

        if current_instruction == "ret" then
            log_interpreter_exit(trace_enabled, stack[top])
            return stack[top]
        elseif current_instruction == "print" then
            print(stack[top])
            top = top - 1
        elseif current_instruction == "push" then
            pc = pc + 1
            top = top + 1
            stack[top] = code[pc]
        elseif code[pc] == "load" then
            pc = pc + 1
            top = top + 1
            -- TODO: might be useful to throw undefined variable exception here
            --       in case the variable is not present in the memory
            -- UPDATE: now that we handle undefined variables at compile time, this is no longer an issue.
            --      BUT, if we separate out compilation and execution stages later on, we will still need
            --           to verify this at runtime.
            stack[top] = memory[code[pc]]
        elseif code[pc] == "store" then
            pc = pc + 1
            memory[code[pc]] = stack[top]
            top = top - 1
        elseif current_instruction == "eq" then
            stack[top - 1] = (stack[top - 1] == stack[top]) and 1 or 0
            top = top - 1
        elseif current_instruction == "neq" then
            stack[top - 1] = (stack[top - 1] ~= stack[top]) and 1 or 0
            top = top - 1
        elseif current_instruction == "lte" then
            stack[top - 1] = (stack[top - 1] <= stack[top]) and 1 or 0
            top = top - 1
        elseif current_instruction == "gte" then
            stack[top - 1] = (stack[top - 1] >= stack[top]) and 1 or 0
            top = top - 1
        elseif current_instruction == "lt" then
            stack[top - 1] = (stack[top - 1] < stack[top]) and 1 or 0
            top = top - 1
        elseif current_instruction == "gt" then
            stack[top - 1] = (stack[top - 1] > stack[top]) and 1 or 0
            top = top - 1
        elseif current_instruction == "not" then
            stack[top] = (stack[top] == 0) and 1 or 0
        elseif current_instruction == "add" then
            stack[top - 1] = stack[top - 1] + stack[top]
            top = top - 1
        elseif current_instruction == "sub" then
            stack[top - 1] = stack[top - 1] - stack[top]
            top = top - 1
        elseif current_instruction == "mul" then
            stack[top - 1] = stack[top - 1] * stack[top]
            top = top - 1
        elseif current_instruction == "div" then
            stack[top - 1] = stack[top - 1] / stack[top]
            top = top - 1
        elseif current_instruction == "mod" then
            stack[top - 1] = stack[top - 1] % stack[top]
            top = top - 1
        elseif current_instruction == "exp" then
            stack[top - 1] = stack[top - 1] ^ stack[top]
            top = top - 1
        elseif current_instruction == "negate" then
            stack[top] = -stack[top]
        else
            error("unknown instruction: '" .. current_instruction .. "'")
        end

        pc = pc + 1
        cycle = cycle + 1
    end
end

--------------------------------------------------------- Main ---------------------------------------------------------

local source = io.read("a")

local ast = parse(source)
print("Abstract Syntax Tree:", pt(ast), "\n")

local code = compile(ast)
print("Compiled Code:", pt(code), "\n")

local memory = {}
local stack = {}
local result = run(code, memory, stack, true)

print("Execution Result = " .. tostring(result))
