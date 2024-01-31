local pt = require "pt".pt

local parse = require "parser".parse
local compile = require "compiler".compile
local run = require "runner".run

local log_levels = require "loglevels"

--------------------------------------------------------- Main ---------------------------------------------------------

-- local log_level = log_levels.everything
-- local log_level = log_levels.everything ~ log_levels.runner.trace_every_cycle
local log_level = log_levels.everything ~ log_levels.runner.everything
-- local log_level = log_levels.nothing

local source = io.read("a")

local ast           = parse(source, log_level)
local main_function = compile(ast, log_level)
local result        = run(main_function, log_level)

print("Execution Result: " .. tostring(result))
