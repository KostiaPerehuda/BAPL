------------------------------ AST Node Factories ------------------------------

--[=[
local function node(tag, ...)
    local labels = table.pack(...)
    local params = table.concat(labels, ", ")
    local fields = {}
    for i, v in ipairs(labels) do fields[i] = v.." = "..v end 
    fields = table.concat(fields, ", ")
    local code  = string.format("return function(%s) return {tag = '%s', %s} end", params, tag, fields)
    return assert(load(code))()
end
--]=]

---[=[
local function node(tag, ...)
    local labels = table.pack(...)
    return function(...)
        local params = table.pack(...)
        local node = { tag = tag }
        for i = 1, #labels do
            node[labels[i]] = params[i]
        end
        return node
    end
end
--]=]

local function number_node(number)
    return { tag = "number", number_value = tonumber(number) }
end

return {
    node = node,

    _number   = number_node,
    _variable = node("variable", "variable_name"),

    _null = node("null"),

    _unary_operator   = node("unary_operator", "operator", "operand"),
    _binary_operator  = node("binop", "left_operand", "operator", "right_operand"),
    _logical_operator = node("logical_operator", "left_operand", "operator", "right_operand"),

    _ternary_operator = node("ternary_operator", "condition", "truthy_expression", "falsy_expression"),

    _is_present_operator = node("is_present_operator", "operand"),
    _or_else_operator    = node("or_else_operator", "left_operand", "right_operand"),

    _new_array = node("new_array", "array_size"),
    _indexed = node("indexed", "variable", "index"),

    
    _local_variable = node("local_variable", "is_optional", "name", "initial_value"),
    _assignment = node("assignment", "target", "expression"),

    _return = node("return", "expression"),
    _print  = node("print", "expression"),

    _skip = node("skip"),
    _block = node("block", "body"),
    _sequence = node("sequence", "first", "second"),

    _if = node("if", "condition", "if_branch", "else_branch"),
    _while = node("while", "condition", "loop_body"),

    _function = node("function", "name", "parameters", "body"),
    _parameters = node("parameters", "formal", "default"),
    
    _call = node("call", "call_site_name", "arguments"),
}
