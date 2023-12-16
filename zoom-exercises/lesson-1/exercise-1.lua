--[[
    Reimplement Homework Activity 11, but using a different approach to handle whitespace
--]]

------------------------------------------------------------------------------------------------------------------------

local lpeg = require "lpeg"

local space = lpeg.S(" \t\n")^1
local optional_space = space^-1

local numeral = lpeg.R("09")^1
local plus = lpeg.P("+")

local pattern = optional_space * numeral * optional_space * (plus * optional_space * numeral * optional_space)^0 * -1

------------------------------------------------------------------------------------------------------------------------

assert(nil ~= pattern:match("1"),             "should match a single-digit numeral")
assert(nil ~= pattern:match("0123"),          "should match a multi-digit numeral")

assert(nil ~= pattern:match("   0123   "),    "should match a numeral surrounded by spaces")
assert(nil ~= pattern:match("\t0123\t"),      "should match a numeral surrounded by tabs")
assert(nil ~= pattern:match("\n0123\n"),      "should match a numeral surrounded by newlines")

assert(nil ~= pattern:match("1+2"),           "should match a sum of two numerals")
assert(nil ~= pattern:match("1+2+3"),         "should match a sum of three numerals")

assert(nil ~= pattern:match("1  +    2"),     "should handle spaces around the plus sign")
assert(nil ~= pattern:match("1\t+\t2"),       "should handle tabs around the plus sign")
assert(nil ~= pattern:match("1\n+\n2"),       "should handle newlines around the plus sign")
assert(nil ~= pattern:match("  1  +  2  "),   "should handle spaces around every element of the expression")

assert(nil == pattern:match("1 - 2"),         "should not match any other character except digits, '+', and whitespace")

assert(nil == pattern:match("+ 1"),           "should not match a leading plus sign")
assert(nil == pattern:match("1 +"),           "should not match a trailing plus sign")
