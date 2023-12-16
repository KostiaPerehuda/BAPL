--[[
    Activity 15 - Matching The Whole Subject

    Modify the previous exercise so that it only succeeds if it matches the whole subject.
--]]

------------------------------------------------------------------------------------------------------------------------

local lpeg = require "lpeg"

local space = lpeg.S(" \t\n")^0

local numeral = lpeg.C(lpeg.R("09")^1) * space
local plus    = lpeg.Cp() * lpeg.P("+") * space

local pattern = space * numeral * (plus * numeral)^0 * -1

------------------------------------------------------------------------------------------------------------------------

print(pattern:match("12+13+25")) --> 12 3 13 6 25
print(pattern:match(" 1 + 2 + 3 ")) --> 1 4 2 8 3

print(pattern:match(" 1 + 2 + 3  --garbage")) --> nil
