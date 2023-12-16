--[[
    Activity 11 - Matching A Summation

    Write a pattern that matches a non-empty list of numerals intercalated with the plus operator (+).
    A plus operator can only appear between two numerals.
    Make sure your pattern allows spaces around any element (numerals and operators).
--]]

------------------------------------------------------------------------------------------------------------------------

local lpeg = require "lpeg"

local space = lpeg.S(" \t\n")^0

local numeral = lpeg.R("09")^1 * space
local plus = lpeg.P("+") * space

local pattern = space * numeral * (plus * numeral)^0 * -1

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
