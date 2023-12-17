local lpeg = require "lpeg"
local pt = require "pt".pt

-------------------------------------------------------- Grammar -------------------------------------------------------

local function to_number_node(num, base)
    return {tag = "number", val = tonumber(num, base)}
end

local space = lpeg.S(" \t\n")^0
local number = lpeg.R("09")^1 / to_number_node * space


local grammar = space * number * -1

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

------------------------------------------------------ Interpreter -----------------------------------------------------

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
