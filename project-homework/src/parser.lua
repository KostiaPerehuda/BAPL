local lpeg = require "lpeg"
local pt = require "pt".pt

local ast = require "abstractsyntax"

local log_levels = require "loglevels".parser

------------------------------------------------------- Grammar --------------------------------------------------------

------------------------------------ Debug -------------------------------------

local function I(message)
    return lpeg.P(function() print(message); return true end)
end

local longest_match = 0

local longest_match_tracker = lpeg.P(function(_,position)
    longest_match = math.max(longest_match, position)
    return true
end)

-------------------------------- Basic Patterns --------------------------------
local digit = lpeg.R("09")
local hex_digit = lpeg.R("09", "af", "AF")

local alpha_char = lpeg.R("AZ", "az")
local alpha_numeric_char = alpha_char + digit

local alpha_char_or_underscore = alpha_char + "_"
local alpha_numeric_char_or_underscore = alpha_numeric_char + "_"

local whitespace = lpeg.S(" \t\r\n")

----------------------------------- Comments -----------------------------------
local line_comment = "#" * (lpeg.P(1) - lpeg.S("\r\n"))^0
local block_comment = "#{" * (lpeg.P(1) - "#}")^0 * "#}"
local comment = block_comment + line_comment

------------------------------------ Spaces ------------------------------------
local space = (whitespace + comment)^0 * longest_match_tracker

--------------------------- Tokens and Reserved Words --------------------------

local function T(t)
    return t * space
end

local reserved_words = {"return", "if", "elseif", "else", "while", "and", "or", "new", "function", "var"}

local reserved = lpeg.P(false)
for i = 1, #reserved_words do
    reserved = reserved + reserved_words[i]
end
reserved = reserved * -alpha_numeric_char_or_underscore

local function RW(word)
    assert(reserved:match(word),
        "'"..word.."' cannot be used as a reserved word! "
        .."You must first insert it into the 'reserved_words' list!")
    return word * -alpha_numeric_char_or_underscore * space
end

------------------------------------ Number ------------------------------------

local e_notation_suffix = (lpeg.S("eE") * lpeg.S"+-"^-1 * digit^1)^-1
local dec_number_body = ((digit^1 * lpeg.P"."^-1 * digit^0) + ("." * digit^1)) * e_notation_suffix

local hex_number_prefix = "0" * lpeg.S("xX")
local hex_number_body = (hex_digit^1 * lpeg.P"."^-1 * hex_digit^0) + ("." * hex_digit^1)

local dec_number = -hex_number_prefix * dec_number_body
local hex_number =  hex_number_prefix * hex_number_body

local number = lpeg.C(dec_number + hex_number) / ast._number * space

---------------------------------- Identifier ----------------------------------
---[[
local exclude_reserved_words = lpeg.P(function(input, position)
    for _, reserved_word in pairs(reserved_words) do
        if input:sub(1, position-1):sub(-#reserved_word) == reserved_word then
           return false
        end
    end
    return true
end)
--]]

local identifier = T(lpeg.C(alpha_char_or_underscore * alpha_numeric_char_or_underscore^0) * exclude_reserved_words)

----------------------------------- Variable -----------------------------------
local variable = identifier / ast._variable

---------------------------------- Expression ----------------------------------

local function fold_left_into_binop_tree(list)
    local tree = list[1]
    for i = 2, #list, 2 do tree = ast._binary_operator(tree, list[i], list[i + 1]) end
    return tree
end

local function fold_right_into_binop_tree(list)
    local tree = list[#list]
    for i = #list - 1, 2, -2 do tree = ast._binary_operator(list[i - 1], list[i], tree) end
    return tree
end

local function fold_left_into_logical(operator)
    return function(list)
        local tree = list[1]
        for i = 2, #list do tree = ast._logical_operator(tree, operator, list[i]) end
        return tree
    end
end

local function fold_left_into_indexed_node(list)
    local tree = list[1]
    for i = 2, #list do tree = ast._indexed(tree, list[i]) end
    return tree
end

local exponential_operator    = T(lpeg.C(lpeg.S("^")))
local negation_operator       = T(lpeg.C(lpeg.S("-!")))
local additive_operator       = T(lpeg.C(lpeg.S("+-")))
local multiplicative_operator = T(lpeg.C(lpeg.S("*/%")))

local comparison_operator = lpeg.C(lpeg.P("==") + "!=" + "<=" + ">=" + "<" +">") * space

local expression  = lpeg.V"expression"

local ternary_operator = lpeg.V"ternary_operator"
local  logical_or = lpeg.V"logical_or"
local logical_and = lpeg.V"logical_and"
local  comparison = lpeg.V"comparison"
local     sum     = lpeg.V"sum"
local     term    = lpeg.V"term"
local   negation  = lpeg.V"negation"
local   exponent  = lpeg.V"exponent"
local     atom    = lpeg.V"atom"
local indexed_var = lpeg.V"indexed_var"
local  new_array  = lpeg.V"new_array"
local function_call = lpeg.V"function_call"
local arguments = lpeg.V"arguments"

local expression = lpeg.P{"expression", expression = ternary_operator,
    ternary_operator =  (logical_or * T"?" * ternary_operator * T":" * ternary_operator / ast._ternary_operator)
                        + logical_or,

     logical_or = lpeg.Ct(logical_and * (RW"or" * logical_and)^0) / fold_left_into_logical("or"),
    logical_and = lpeg.Ct( comparison * (RW"and" * comparison)^0) / fold_left_into_logical("and"),
     comparison = lpeg.Ct(  sum    * (  comparison_operator   *   sum   )^0) / fold_left_into_binop_tree,
        sum     = lpeg.Ct(  term   * (   additive_operator    *   term  )^0) / fold_left_into_binop_tree,
        term    = lpeg.Ct(negation * (multiplicative_operator * negation)^0) / fold_left_into_binop_tree,
      negation  = (negation_operator * negation / ast._unary_operator) + exponent,
      exponent  = lpeg.Ct(  atom   * (  exponential_operator  *   atom  )^0) / fold_right_into_binop_tree,

        atom    = (T"(" * expression * T")") + number + new_array + function_call + indexed_var,

     new_array  = RW"new" * lpeg.Ct((T"[" * expression * T"]")^1) / ast._new_array,
    indexed_var = lpeg.Ct(variable * (T"[" * expression * T"]")^0) / fold_left_into_indexed_node,

    function_call = identifier * T"(" * arguments * T")" / ast._call,
    arguments = lpeg.Ct((expression * (T"," * expression)^0)^-1),
}

------------------------- Local Variable Declarations --------------------------
local local_var = RW"var" * identifier * (T"=" * expression)^-1 / ast._local_variable

---------------------------------- Assignment ----------------------------------
local assignment_target = lpeg.Ct(variable * (T"[" * expression * T"]")^0) / fold_left_into_indexed_node
local assignment = assignment_target * T"=" * expression / ast._assignment

------------------------------- Return Statement -------------------------------
local return_statement = RW"return" * expression / ast._return

------------------------------- Print Statement --------------------------------
local print_statement = T"@" * expression / ast._print

----------------------------- Sequences and Blocks -----------------------------

local function fold_right_to_sequence_node(statements)
    if #statements == 0 then return ast._skip() end

    local node = statements[#statements]
    for i = #statements - 1, 1, -1 do
        node = ast._sequence(statements[i], node)
    end
    return node
end

local function fold_right_to_if_node(list)
    local last_if_node_index = #list - (#list % 2) - 1
    local node = ast._if(list[last_if_node_index], list[last_if_node_index + 1], list[last_if_node_index + 2])
    for i = last_if_node_index - 1, 1, -2 do node = ast._if(list[i - 1], list[i], node) end
    return node
end

local delimiter = T";"^1

local sequence  = lpeg.V"sequence"
local block     = lpeg.V"block"
local statement    = lpeg.V"statement"
local if_statement = lpeg.V"if_statement"
local while_statement = lpeg.V"while_statement"
local function_header = lpeg.V"function_header"
local function_decl = lpeg.V"function_decl"
local function_def = lpeg.V"function_def"
local call_statement = lpeg.V"call_statement"
local function_params = lpeg.V"function_params"

-- TODO: a "block" is a purely syntactic feature for now, it has no meaning,
--       for the compiler.
--       The parser just drops the block-start and block-end anchors.
--       Will most probably be changed in the future when we will implement
--       local variables and stack frames.
local program = lpeg.P{"functions",

    functions = lpeg.Ct((function_decl + function_def)^0),

    function_decl = (function_header * T";") / ast._function,
    function_def = (function_header * block) / ast._function,

    function_header = RW"function" * identifier * T"(" * function_params * T")",
    function_params = ((lpeg.Ct(identifier * (T"," * identifier)^0) * (T"=" * expression)^-1) + lpeg.Cc({}))
                        / ast._parameters,

    sequence = lpeg.Ct((statement * (delimiter * statement)^0)^-1) / fold_right_to_sequence_node * delimiter^-1,
    block    = T"{" * sequence * T"}" / ast._block,
    
    statement = block
                + assignment
                + call_statement
                + return_statement
                + print_statement
                + if_statement
                + while_statement
                + local_var,

    if_statement = lpeg.Ct(
        (RW"if" * expression * block)
        * (RW"elseif" * expression * block)^0
        * (RW"else" * block)^-1
        ) / fold_right_to_if_node,

    while_statement = RW"while" * expression * block / ast._while,

    call_statement = identifier * T"(" * arguments * T")" / ast._call,
    arguments = lpeg.Ct((expression * (T"," * expression)^0)^-1),
}
--------------------------------------------------------------------------------

local grammar = space * program * -1

-------------------------------------------------------- Parser --------------------------------------------------------

local function get_line_and_column(input, position)
    input = input .. "\n"
    line_number = 0

    for line in input:gmatch(".-\n") do
        line_number = line_number + 1
        position = position - line:len()
        if position <= 0 then
            trimmed_line = (line:sub(-2, -2) == "\r") and line:sub(1, -3) or line:sub(1, -2)
            return line_number, position + line:len(), trimmed_line
        end
    end
end

local function syntax_error(input, longest_match)
    -- longest match == next char to consume
    line_num, col_num, line = get_line_and_column(input, longest_match)
    io.stderr:write(string.format("Syntax Error at Line %d, Col %d! ('%s')\n", line_num, col_num, line))
    io.stderr:write(string.format("Unexpected Symbol '%s' after '%s'\n",
                                        line:sub(col_num, col_num), line:sub(1, col_num-1)))
    os.exit(1)
  end

local function parse(input, log_level)
    local ast = grammar:match(input)
    if not ast then syntax_error(input, longest_match) end

    if log_level and (log_level & log_levels.display_ast ~= 0) then
        print("Abstract Syntax Tree: " .. pt(ast) .. "\n")
    end
    
    return ast
end

return { parse = parse }