local pt = require "pt".pt

local parse = require "parser".parse
local compile = require "compiler".compile
local run = require "runner".run

--------------------------------------------------------- Main ---------------------------------------------------------

local source = io.read("a")

local ast = parse(source)
print("Abstract Syntax Tree:", pt(ast), "\n")

local main_function = compile(ast)
print("Compiled Code:", pt(main_function), "\n")

local result = run(main_function, true)
print("Execution Result = " .. pt(result))
