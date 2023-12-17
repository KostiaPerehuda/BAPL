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

------------------------------------ Space -------------------------------------
local space_token = lpeg.S(" \t\n")^0
------------------------------------ Number ------------------------------------
local int_number_body = lpeg.R("09")^1

local hex_number_body = lpeg.R("09", "af", "AF")^1
local hex_number_prefix = "0" * lpeg.S("xX")

local int_number = -hex_number_prefix * lpeg.C(int_number_body) / to_int_number_node
local hex_number =  hex_number_prefix * lpeg.C(hex_number_body) / to_hex_number_node

local number_token = (int_number + hex_number) * space_token
--------------------------------------------------------------------------------

local grammar = space_token * number_token * -1

-------------------------------------------------------- Parser --------------------------------------------------------

local function parse(input)
    return grammar:match(input)
end

------------------------------------------------------- Compiler -------------------------------------------------------

local function compile (ast)
    if ast.tag == "number" then
        return {"push", ast.val}
    end
end

----------------------------------------------------- Interpreter ------------------------------------------------------

local function run (code, stack)
    local pc = 1
    local top = 0
    while pc <= #code do
        if code[pc] == "push" then
            pc = pc + 1
            top = top + 1
            stack[top] = code[pc]
        else
            error("unknown instruction")
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
