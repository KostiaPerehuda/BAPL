--[[
    Activity 13 - Position Capture

    Modify the previous exercise so that it returns all numerals in the subject
    intercalated with the positions of the intercalated plus operators, like this:

        print(patt:match("12+13+25")) --> 12 3 13 6 25
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
