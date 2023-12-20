local lpeg = require "lpeg"
local pt = require "pt".pt

------------------------------------------------------- Grammar --------------------------------------------------------

local function to_number_node(...)
    return { tag = "number", number_value = tonumber(...) }
end

local function to_dec_number_node(num)
    return to_number_node(num)
end

local function to_hex_number_node(num)
    return to_number_node(num, 16)
end

local function to_variable_node(variable_name)
    return { tag = "variable", variable_name = variable_name }
end

-- Convert a list {n1, "+", n2, "+", n3, ...} into a tree
-- {...{ operator = "+", left_operand = {operator = "+", left_operand = n1, right_operand = n2}, right_operand = n3}...}
local function fold_left_into_binop_tree(lst)
    local tree = lst[1]
    for i = 2, #lst, 2 do
        tree = {
            tag = "binop",
            left_operand = tree,
            operator = lst[i],
            right_operand = lst[i + 1],
        }
    end
    return tree
end

local function fold_right_into_binop_tree(lst)
    local tree = lst[#lst]
    for i = #lst-1, 2, -2 do
        tree = {
            tag = "binop",
            left_operand = lst[i - 1],
            operator = lst[i],
            right_operand = tree,
        }
    end
    return tree
end

local function apply_unary_minus_operator(expression)
    return { tag = "unary_minus", operand = expression }
end

local function to_assignment_node(identifier, expression)
    return { tag = "assignment", assignment_target = identifier, expression = expression }
end

-------------------------------- Basic Patterns --------------------------------
local space = lpeg.S(" \t\n")^0

local digit = lpeg.R("09")
local hex_digit = lpeg.R("09", "af", "AF")

local alpha_char = lpeg.R("AZ", "az")
local alpha_numeric_char = alpha_char + digit
------------------------------------ Number ------------------------------------
local e_notation_suffix = (lpeg.S("eE") * lpeg.P"-"^-1 * digit^1)^-1
local dec_number_body = ((digit^1 * lpeg.P"."^-1 * digit^0) + ("." * digit^1)) * e_notation_suffix

local hex_number_prefix = "0" * lpeg.S("xX")
local hex_number_body = hex_digit^1

local dec_number = -hex_number_prefix * lpeg.C(dec_number_body) / to_dec_number_node
local hex_number =  hex_number_prefix * lpeg.C(hex_number_body) / to_hex_number_node

local number = (dec_number + hex_number) * space
---------------------------------- Identifier ----------------------------------
local alpha_char_or_underscore = alpha_char + "_"
local alpha_numeric_char_or_underscore = alpha_numeric_char + "_"

local identifier = lpeg.C(alpha_char_or_underscore * alpha_numeric_char_or_underscore^0) * space
----------------------------------- Variable -----------------------------------
local variable = identifier / to_variable_node
---------------------------------- Expression ----------------------------------
local unary_minus_operator    = "-" * space

local exponential_operator    = lpeg.C(lpeg.S("^"))   * space
local multiplicative_operator = lpeg.C(lpeg.S("*/%")) * space
local additive_operator       = lpeg.C(lpeg.S("+-"))  * space

local comparison_operator = lpeg.C(lpeg.P("==") + "!=" + "<=" + ">=" + "<" +">") * space

local  open_bracket = "(" * space
local close_bracket = ")" * space

local expression  = lpeg.V"expression"
local comparison  = lpeg.V"comparison"
local     sum     = lpeg.V"sum"
local     term    = lpeg.V"term"
local   exponent  = lpeg.V"exponent"
local unary_minus = lpeg.V"unary_minus"
local     atom    = lpeg.V"atom"

local expression = lpeg.P{"expression", expression = comparison,
    comparison  = lpeg.Ct(   sum      * (  comparison_operator   *     sum     )^0) / fold_left_into_binop_tree,
       sum      = lpeg.Ct(   term     * (   additive_operator    *     term    )^0) / fold_left_into_binop_tree,
       term     = lpeg.Ct(unary_minus * (multiplicative_operator *  unary_minus)^0) / fold_left_into_binop_tree,
    unary_minus = (unary_minus_operator * unary_minus / apply_unary_minus_operator) + exponent,
     exponent   = lpeg.Ct(   atom     * (  exponential_operator  *     atom    )^0) / fold_right_into_binop_tree,
       atom     = (open_bracket * expression * close_bracket) + number + variable,
}
---------------------------------- Assignment ----------------------------------
local assignment_operator = "=" * space
local assignment = identifier * assignment_operator * expression / to_assignment_node
--------------------------------------------------------------------------------

local grammar = space * assignment * -1

-------------------------------------------------------- Parser --------------------------------------------------------

local function parse(input)
    return grammar:match(input)
end

------------------------------------------------------- Compiler -------------------------------------------------------

local function add_opcode(state, opcode)
    local code = state.code
    code[#code + 1] = opcode
end

local opcode_from_operator = {
    ["=="] = "eq", ["!="] = "neq", ["<="] = "lte", [">="] = "gte", ["<"] = "lt", [">"] = "gt",
    ["+"] = "add", ["-"] = "sub",
    ["*"] = "mul", ["/"] = "div", ["%"] = "mod",
    ["^"] = "exp",
}

local function get_opcode_from_operator(operator)
    return opcode_from_operator[operator] or error("invalid tree")
end

local function generate_code_from_expression(state, expression)
    if expression.tag == "number" then
        add_opcode(state, "push")
        add_opcode(state, expression.number_value)
    elseif expression.tag == "variable" then
        add_opcode(state, "load")
        add_opcode(state, expression.variable_name)
    elseif expression.tag == "binop" then
        generate_code_from_expression(state, expression.left_operand)
        generate_code_from_expression(state, expression.right_operand)
        add_opcode(state, get_opcode_from_operator(expression.operator))
    elseif expression.tag == "unary_minus" then
        generate_code_from_expression(state, expression.operand)
        add_opcode(state, "negate")
    else
        error("invalid tree")
    end
end

local function generate_code_from_statement(state, statement)
    if statement.tag == "assignment" then
        generate_code_from_expression(state, statement.expression)
        add_opcode(state, "store")
        add_opcode(state, statement.assignment_target)
    else
        error("invalid tree")
    end
end

local function compile(ast)
    local state = { code = {} }
    generate_code_from_statement(state, ast)
    return state.code
end

----------------------------------------------------- Interpreter ------------------------------------------------------

local function log_executed_instruction(instruction, pc, stack_top)
    if instruction == "push" then instruction = instruction.." "..tostring(stack_top) end
    print("Executed '"..instruction.."'.\nPC = '"..pc.."'.\tStack Top = '"..tostring(stack_top).."'.")
end

local function run(code, memory, stack, trace_enabled)
    local pc = 1
    local top = 0
    while pc <= #code do
        local current_instruction = code[pc]
        if current_instruction == "push" then
            pc = pc + 1
            top = top + 1
            stack[top] = code[pc]
        elseif code[pc] == "load" then
            pc = pc + 1
            top = top + 1
            -- TODO: might be useful to throw undefined variable exception here
            --       in case the variable is not present in the memory
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

        if trace_enabled then log_executed_instruction(current_instruction, pc, stack[top]) end
    end
end

--------------------------------------------------------- Main ---------------------------------------------------------

local source = io.read("a")

local ast = parse(source)
print("Abstract Syntax Tree:", pt(ast), "\n")

local code = compile(ast)
print("Compiled Code:", pt(code), "\n")

local memory = { const1 = 1, const10 = 10 }
local stack = {}
run(code, memory, stack, true)

print("Execution Result:", memory.result)
