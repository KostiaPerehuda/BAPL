local lpeg = require "lpeg"
local pt = require "pt"

----------------------------------------------------
local function node (num)
  return {tag = "number", val = tonumber(num)}
end

local space = lpeg.S(" \t\n")^0
local numeral = lpeg.R("09")^1 / node  * space


local opA = lpeg.C(lpeg.S"+-") * space


-- Convert a list {n1, "+", n2, "+", n3, ...} into a tree
-- {...{ op = "+", e1 = {op = "+", e1 = n1, n2 = n2}, e2 = n3}...}
local function foldBin (lst)
  local tree = lst[1]
  for i = 2, #lst, 2 do
    tree = { tag = "binop", e1 = tree, op = lst[i], e2 = lst[i + 1] }
  end
  return tree
end


local exp = lpeg.Ct(numeral * (opA * numeral)^0) / foldBin

local function parse (input)
  return exp:match(input)
end

----------------------------------------------------

local function addCode (state, op)
  local code = state.code
  code[#code + 1] = op
end


local ops = {["+"] = "add", ["-"] = "sub"}

local function codeExp (state, ast)
  if ast.tag == "number" then
    addCode(state, "push")
    addCode(state, ast.val)
  elseif ast.tag == "binop" then
    codeExp(state, ast.e1)
    codeExp(state, ast.e2)
    addCode(state, ops[ast.op])
  else error("invalid tree")
  end
end

local function compile (ast)
  local state = { code = {} }
  codeExp(state, ast)
  return state.code
end

----------------------------------------------------

local function run (code, stack)
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
    else error("unknown instruction")
    end
    pc = pc + 1
  end
end


local input = io.read("a")
local ast = parse(input)
print(pt.pt(ast))
local code = compile(ast)
print(pt.pt(code))
local stack = {}
run(code, stack)
print(stack[1])
