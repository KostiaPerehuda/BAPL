local lpeg = require "lpeg"
local pt = require "pt".pt

------------------------------------------------------- Grammar --------------------------------------------------------

local function to_number_node(num, base)
    return {tag = "number", val = tonumber(num, base)}
end

local function to_int_number_node(num)
    return to_number_node(num, 10)
end

local function to_hex_number_node(num)
    return to_number_node(num, 16)
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

------------------------------------ Space -------------------------------------
local space = lpeg.S(" \t\n")^0
------------------------------------ Number ------------------------------------
local int_number_body = lpeg.R("09")^1

local hex_number_body = lpeg.R("09", "af", "AF")^1
local hex_number_prefix = "0" * lpeg.S("xX")

local int_number = -hex_number_prefix * lpeg.C(int_number_body) / to_int_number_node
local hex_number =  hex_number_prefix * lpeg.C(hex_number_body) / to_hex_number_node

local number = (int_number + hex_number) * space
---------------------------- Arithmetic Expressions ----------------------------
local multiplicative_operator = lpeg.C(lpeg.S("*/")) * space
local additive_operator       = lpeg.C(lpeg.S("+-")) * space

local term = lpeg.Ct(number * (multiplicative_operator * number)^0) / fold_left_into_binop_tree
local sum  = lpeg.Ct( term  * (   additive_operator    *  term )^0) / fold_left_into_binop_tree

local arithmetic_expression = sum
--------------------------------------------------------------------------------

local grammar = space * sum * -1

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
    ["+"] = "add", ["-"] = "sub",
    ["*"] = "mul", ["/"] = "div",
}

local function get_opcode_from_operator(operator)
    return opcode_from_operator[operator] or error("invalid tree")
end

local function generate_code_from_expression(state, expression)
    if expression.tag == "number" then
        add_opcode(state, "push")
        add_opcode(state, expression.val)
    elseif expression.tag == "binop" then
        generate_code_from_expression(state, expression.left_operand)
        generate_code_from_expression(state, expression.right_operand)
        add_opcode(state, get_opcode_from_operator(expression.operator))
    else
        error("invalid tree")
    end
end

local function compile(ast)
    local state = { code = {} }
    generate_code_from_expression(state, ast)
    return state.code
end

----------------------------------------------------- Interpreter ------------------------------------------------------

local function run(code, stack)
    local pc = 1
    local top = 0
    while pc <= #code do
        if code[pc] == "push" then
            pc = pc + 1
            top = top + 1
            stack[top] = code[pc]
        elseif code[pc] == "add" then
            stack[top - 1] = stack[top - 1] + stack[top]
            top = top - 1
        elseif code[pc] == "sub" then
            stack[top - 1] = stack[top - 1] - stack[top]
            top = top - 1
        elseif code[pc] == "mul" then
            stack[top - 1] = stack[top - 1] * stack[top]
            top = top - 1
        elseif code[pc] == "div" then
            stack[top - 1] = stack[top - 1] / stack[top]
            top = top - 1
        else
            error("unknown instruction: '" .. code[pc] .. "'")
        end
        pc = pc + 1
    end
end

--------------------------------------------------------- Main ---------------------------------------------------------

local source = io.read("a")

local ast = parse(source)
print("Abstract Syntax Tree:", pt(ast), "\n")

local code = compile(ast)
print("Compiled Code:", pt(code), "\n")

local stack = {}
run(code, stack)

print("Execution Result:", stack[1])
