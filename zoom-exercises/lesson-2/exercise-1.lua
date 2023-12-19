--[[
    Repetitions - Matching Exact Number of Repetitions of a Pattern
--]]

local lpeg = require "lpeg"

--[[
    Approach 1: Using lookaheads
        If you want to match p exactly n times then:
            1. Check using a lookahead if you have p reperated AT LEAST n times.
            2. Match p AT MOST n times.
                Since matching is possessive and we have p repeated at least n times
                    this will consume n repetitions of p
    
        Note: if your p accepts an empty string, then this will fail,
            because "matching p at least n times" will never terminate
--]]

local function Ex(p, n) return (#(p^n))*p^-n end

print(Ex(lpeg.P("H"), 2):match("Hello"))  --> nil
print(Ex(lpeg.P("H"), 2):match("HHello")) --> 3

--[[
    Approach 2: Just concatenate p exactly n times
--]]

local function Ex(p, n)
    result = lpeg.P""
    for i = 1, n do result = result * p end
    return result
end

print(Ex(lpeg.P("H"), 2):match("Hello"))  --> nil
print(Ex(lpeg.P("H"), 2):match("HHello")) --> 3
