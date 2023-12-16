--[[
    Greedy vs. Possessive

    print(("AAABAAA:B"):match(".*:")) --> AAABAAA

    a) Rewrite the Lua expression above in LPeg.

    b) What happens in both expressions (Lua and LPeg) if the subject is (“AAAB:AAA:B”)?
--]]

------------------------------------------------------------------------------------------------------------------------

print(("AAABAAA:B"):match(".*:"))  --> AAABAAA
print(("AAAB:AAA:B"):match(".*:")) --> AAAB:AAA:
print()

------------------------------------------------------------------------------------------------------------------------

local lpeg = require "lpeg"

local pattern;


pattern = lpeg.C( lpeg.P(1)^0 * ":" )
-- possessive, will always fail because lpeg.P(1)^0 will consume all the input
-- and matching ":" will always fail as it will try to match it against empty string
print(pattern:match("AAABAAA:B"))  --> nil
print(pattern:match("AAAB:AAA:B")) --> nil
print()


pattern = lpeg.C( (lpeg.P(1)-":")^0 * ":" )
-- equivalent to lazy RegExp, as it will stop matching lpeg.P(1) when it sees the first ":", and will mtach ":" next
print(pattern:match("AAABAAA:B"))  --> AAABAAA:
print(pattern:match("AAAB:AAA:B")) --> AAAB:
print()


pattern = lpeg.C{"grammar",
    grammar = (1 * lpeg.V"grammar") + ":",
}
-- greedy pattern, grammars support backtracking, ordered choice makes the pattern greedy, as ':' is matched only when
-- first option, that is (1 * lpeg.V"grammar") failed
print(pattern:match("AAABAAA:B")) --> AAABAAA:
print(pattern:match("AAAB:AAA:B")) --> AAAB:AAA:
print()


pattern = lpeg.C{"grammar",
    grammar = ":" + (1 * lpeg.V"grammar")
}
-- lazy pattern, grammars support backtracking, ordered choice makes the pattern lazy, as ':' is the first choice to
-- be tried to match, and if it matches, the whole grammar matches
print(pattern:match("AAABAAA:B")) --> AAABAAA:
print(pattern:match("AAAB:AAA:B")) --> AAAB:
print()

------------------------------------------------------------------------------------------------------------------------

-- Bonus: Lazy match with RegExp
print(("AAAB:AAA:B"):match(".-:")) --> AAAB:
