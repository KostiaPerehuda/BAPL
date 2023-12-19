--[[
    Try to write patterns to match greedy & lazy repetitions.
        Subject: "hello!hello!hello"
        Pattern: ".*!"
        
        Greedy match: "hello!hello!"
        Lazy match: "hello!"
--]]

local lpeg = require "lpeg"

local greedy_pattern = lpeg.C{"grammar",
    grammar = (1 * lpeg.V"grammar") + "!"
}

local lazy_pattern = lpeg.C{"grammar",
    grammar = "!" + (1 * lpeg.V"grammar")
}

print(greedy_pattern:match("hello!hello!hello")) --> "hello!hello!"
print(  lazy_pattern:match("hello!hello!hello")) --> "hello!"
