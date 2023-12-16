--[[
    Activity 8 - Getting Started

    Check if you have LPeg properly installed in your machine by redoing some examples from the previous lecture.
--]]

------------------------------------------------------------------------------------------------------------------------

local lpeg = require "lpeg"

-- create a pattern
local p = lpeg.P("hello")

-- match it against a subject
print(lpeg.match(p, "hello world")) --> 6
print(lpeg.match(p, "hi world"))    --> nil
