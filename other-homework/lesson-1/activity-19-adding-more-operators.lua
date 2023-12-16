--[[
    Activity 19 - Adding More Operators

    a) Add a remainder operator (%) to the language, with the same priority as the other multiplicative operators.

    b) Add an exponential operator (^) to the language, with a higher priority than the multiplicative operators.
    Use the same concepts we used when we added multiplicative operators.
    You will probably need a new kind of expression, besides 'term' and 'exp'.
--]]

------------------------------------------------------------------------------------------------------------------------

local lpeg = require "lpeg"

local space = lpeg.S(" \t\n")^0

local number = ((lpeg.S("+-")^-1 * lpeg.R("09")^1) / tonumber) * space

local additive_op       = lpeg.C(lpeg.S("+-")) * space
local multiplicative_op = lpeg.C(lpeg.S("*/%")) * space
local exponential_op    = lpeg.C(lpeg.S("^"))  * space

function evaluate_binary_operation(left_operand, operator, right_operand)
    if operator == "+" then
        return left_operand + right_operand
    elseif operator == "-" then
        return left_operand - right_operand
    elseif operator == "*" then
        return left_operand * right_operand
    elseif operator == "/" then
        return left_operand / right_operand
    elseif operator == "%" then
        return left_operand % right_operand
    elseif operator == "^" then
        return left_operand ^ right_operand
    else
        error("unknown operator")
    end
end

function fold_left (lst)
    local acc = lst[1]
    for i = 2, #lst, 2 do
        acc = evaluate_binary_operation(acc, lst[i], lst[i+1])
    end
    return acc
end

function fold_right(lst)
    local acc = lst[#lst]
    for i = #lst-1, 2, -2 do
        acc = evaluate_binary_operation(lst[i-1], lst[i], acc)
    end
    return acc
end

local exponent = lpeg.Ct( number  * (  exponential_op  *  number )^0) / fold_right
local term     = lpeg.Ct(exponent * (multiplicative_op * exponent)^0) / fold_left
local sum      = lpeg.Ct(  term   * (   additive_op    *   term  )^0) / fold_left

local expression = space * sum * -1

------------------------------------------------------------------------------------------------------------------------

assert(0 == expression:match("2 % 2"), "should handle remainder")

assert( 5 == expression:match("2 % 4 + 3"), "should prioritize remainder over addition")
assert( 3 == expression:match("2 + 4 % 3"), "should prioritize remainder over addition")

assert(-3 == expression:match("3 % 3 - 3"), "should prioritize remainder over subtraction")
assert( 3 == expression:match("3 - 3 % 3"), "should prioritize remainder over subtraction")

assert( 1 == expression:match("3 * 3 % 2"), "should not prioritize remainder over multiplication")
assert( 0 == expression:match("3 % 3 * 2"), "should not prioritize remainder over multiplication")

assert( 1 == expression:match("3 / 3 % 2"), "should not prioritize remainder over division")
assert( 0 == expression:match("3 % 3 / 2"), "should not prioritize remainder over division")

------------------------------------------------------------------------------------------------------------------------

assert(8 == expression:match("2 ^ 3"), "should handle exponent")

assert(512 == expression:match("2 ^ 3 ^ 2"), "exponent should be right-associative")

assert( 9 == expression:match("2 ^ 3 + 1"), "should prioritize exponent over addition")
assert( 9 == expression:match("1 + 2 ^ 3"), "should prioritize exponent over addition")

assert(  7 == expression:match("2 ^ 3 - 1"), "should prioritize exponent over subtraction")
assert( -7 == expression:match("1 - 2 ^ 3"), "should prioritize exponent over subtraction")

assert( 32 == expression:match("4 * 2 ^ 3"), "should prioritize exponent over multiplication")
assert( 32 == expression:match("2 ^ 3 * 4"), "should prioritize exponent over multiplication")

assert(0.5 == expression:match("4 / 2 ^ 3"), "should prioritize exponent over division")
assert(  2 == expression:match("2 ^ 3 / 4"), "should prioritize exponent over division")

assert(1 == expression:match("2 ^ 2 % 3"), "should prioritize exponent over remainder")
assert(2 == expression:match("2 % 2 ^ 3"), "should prioritize exponent over remainder")
