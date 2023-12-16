--[[
    Activity 17 - Adding An Optional Sign To Numerals

    Add an optional sign (+) or (-) to numerals.
--]]

------------------------------------------------------------------------------------------------------------------------

local lpeg = require "lpeg"

local space = lpeg.S(" \t\n")^0

local number = ((lpeg.S("+-")^-1 * lpeg.R("09")^1) / tonumber) * space
local plus    = lpeg.P("+") * space

local function fold(lst)
    local acc = lst[1]
    for i = 2, #lst do
        acc = acc + lst[i]
    end
    return acc
end

local pattern = space * lpeg.Ct(number * (plus * number)^0) / fold * -1

------------------------------------------------------------------------------------------------------------------------

assert(6 == pattern:match("1 + 2 + 3"), "should add positive numbers")

assert(6 == pattern:match("1 + +2 + 3"), "should allow optional plus sign next to a number")
assert(0 == pattern:match("1 + -4 + 3"), "should allow optional minus sign next to a number")

assert(nil == pattern:match("1 + -+4 + 3"), "should not allow more than one sign next to a number")
