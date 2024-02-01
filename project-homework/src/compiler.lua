local pt = require "pt".pt
local ast = require "abstractsyntax"

local log_levels = require "loglevels".compiler

------------------------------------------------------- Compiler -------------------------------------------------------

local Compiler = { functions = {}, globals = {}, nglobals = 0, locals = {} }

function Compiler:add_opcode(...)
    local code = self.code
    for _, opcode in ipairs({...}) do
        code[#code + 1] = opcode
    end
end

local opcode_from_binary_operator = {
    ["=="] = "eq", ["!="] = "neq", ["<="] = "lte", [">="] = "gte", ["<"] = "lt", [">"] = "gt",
    ["+"] = "add", ["-"] = "sub",
    ["*"] = "mul", ["/"] = "div", ["%"] = "mod",
    ["^"] = "exp",
}

local function get_opcode_from_binary_operator(operator)
    return opcode_from_binary_operator[operator] or error("invalid tree")
end

local opcode_from_unary_operator = {
    ["-"] = "negate", ["!"] = "not",
}

local function get_opcode_from_unary_operator(operator)
    return opcode_from_unary_operator[operator] or error("invalid tree")
end

local jump_opcode_from_logical_operator = {
    ["and"] = "jump_if_zero_or_pop", ["or"] = "jump_if_not_zero_or_pop"
}

local function get_jump_opcode_from_logical_operator(operator)
    return jump_opcode_from_logical_operator[operator] or error("invalid tree")
end

function Compiler:global_variable_index_from_name(variable_name)
    local num = self.globals[variable_name]
    if not num then
        num = self.nglobals + 1
        self.nglobals = num
        self.globals[variable_name] = num
    end
    return num
end

function Compiler:assert_variable_is_defined(variable_name)
    assert(self.globals[variable_name], "Varible '" .. variable_name .. "' is referenced before being defined!")
end

function Compiler:find_local(name)
    local locals = self.locals
    for i = #locals, 1, -1 do
        if name == locals[i].name then
            return i, locals[i].is_optional
        end
    end
    local parameters = self.parameters.formal
    for i = 1, #parameters do
        if name == parameters[i] then
            return i - #parameters, false
        end
    end
    return nil, nil
end

function Compiler:current_position()
    return #self.code
end

function Compiler:generate_jump(jump)
    self:add_opcode(jump or "jump", 0)
    return self:current_position()
end

function Compiler:generate_jump_to(position, jump_factory)
    self:point_jump_to((jump_factory or self.generate_jump)(self), position)
end

function Compiler:generate_jump_if_zero()
    return self:generate_jump("jump_if_zero")
end

function Compiler:generate_jump_if_null()
    return self:generate_jump("jump_if_null")
end

function Compiler:generate_jump_if_not_null_or_pop()
    return self:generate_jump("jump_if_not_null_or_pop")
end

function Compiler:point_jump_to(jump, position)
    self.code[jump] = position - jump
end

function Compiler:point_jump_to_here(jump)
    self:point_jump_to(jump, self:current_position())
end


function Compiler:find_overload(name, number_of_parameters)
    return self.functions[name.."@"..number_of_parameters]
end


function Compiler:resolve_call(call_node)
    local call_site = self:find_overload(call_node.call_site_name, #call_node.arguments)
    if call_site then return call_site, false end

    call_site = self:find_overload(call_node.call_site_name, #call_node.arguments + 1)
    if call_site and call_site.parameters.default then return call_site, true end

    return nil, nil
end

local function create_pretty_call_site_name(call_node)
    return "<'" .. call_node.call_site_name .. "' with " .. #call_node.arguments .. " agrument(s)>"
end

function Compiler:generate_code_from_call(call_node)
    local call_site, called_with_default_argument = self:resolve_call(call_node)
    if not call_site then
        error("Compilation Error: cannot resolve function call to " .. create_pretty_call_site_name(call_node))
    end

    for _, argument in ipairs(call_node.arguments) do
        self:generate_code_from_expression(argument)
    end

    if called_with_default_argument then
        self:generate_code_from_expression(call_site.parameters.default)
    end

    self:add_opcode("call", call_site)
end

function Compiler:generate_code_from_expression(expression)
    if expression.tag == "number" then
        self:add_opcode("push", expression.number_value)
    elseif expression.tag == "null" then
        self:add_opcode("push", "null")
    elseif expression.tag == "call" then
        self:generate_code_from_call(expression)
    elseif expression.tag == "variable" then
        -- UPDATE: with introduction of the functions and branches, this check has to live at run-time only
        -- self:assert_variable_is_defined(expression.variable_name)
        local local_index = self:find_local(expression.variable_name)
        if local_index then
            self:add_opcode("load_local", local_index)
        else
            self:add_opcode("load", self:global_variable_index_from_name(expression.variable_name))
        end
    elseif expression.tag == "indexed" then
        self:generate_code_from_expression(expression.variable)
        self:generate_code_from_expression(expression.index)
        self:add_opcode("array_load")
    elseif expression.tag == "new_array" then
        for i = 1, #expression.array_size do
            self:generate_code_from_expression(expression.array_size[i])
        end
        self:add_opcode("new_array", #expression.array_size)
    elseif expression.tag == "binop" then
        self:generate_code_from_expression(expression.left_operand)
        self:generate_code_from_expression(expression.right_operand)
        self:add_opcode(get_opcode_from_binary_operator(expression.operator))
    elseif expression.tag == "logical_operator" then
        self:generate_code_from_expression(expression.left_operand)
        local jump = self:generate_jump(get_jump_opcode_from_logical_operator(expression.operator))
        self:generate_code_from_expression(expression.right_operand)
        self:point_jump_to_here(jump)
    elseif expression.tag == "unary_operator" then
        self:generate_code_from_expression(expression.operand)
        self:add_opcode(get_opcode_from_unary_operator(expression.operator))
    elseif expression.tag == "ternary_operator" then
        self:generate_code_from_expression(expression.condition)
        local jump_to_falsy_expression = self:generate_jump_if_zero()

        self:generate_code_from_expression(expression.truthy_expression)
        local jump_to_end = self:generate_jump()

        self:point_jump_to_here(jump_to_falsy_expression)
        self:generate_code_from_expression(expression.falsy_expression)

        self:point_jump_to_here(jump_to_end)
    elseif expression.tag == "is_present_operator" then
        self:generate_code_from_expression(expression.operand)
        local jump_to_false = self:generate_jump_if_null()

        self:generate_code_from_expression(ast._number(1))
        local jump_to_end = self:generate_jump()

        self:point_jump_to_here(jump_to_false)
        self:generate_code_from_expression(ast._number(0))

        self:point_jump_to_here(jump_to_end)
    elseif expression.tag == "or_else_operator" then
        self:generate_code_from_expression(expression.left_operand)
        local jump = self:generate_jump_if_not_null_or_pop()
        self:generate_code_from_expression(expression.right_operand)
        self:point_jump_to_here(jump)
    else
        error("Cannot generate code; Invalid expression tree: " .. pt(expression))
    end
end


function Compiler:type_check_call(call_node)
    for i, argument in ipairs(call_node.arguments) do
        if self:is_of_optional_type(argument) then
            error("Type Error: Function Calls cannot accept arguments of optional type! "
            .. "Rule violated by argument number '" .. i .. "'! In " .. pt(call_node))
        end
    end

    local call_site, _ = self:resolve_call(call_node)
    if not call_site then
        error("Compilation Error: cannot resolve function call to " .. create_pretty_call_site_name(call_node))
    end

    return call_site.returns_optional
end


function Compiler:is_of_optional_type(expression)
    if expression.tag == "number" then
        return false
    elseif expression.tag == "null" then
        return true
    elseif expression.tag == "call" then
        return self:type_check_call(expression)
    elseif expression.tag == "variable" then 
        local local_index, is_optional = self:find_local(expression.variable_name)
        if local_index then
            return is_optional
        else
            return true
        end
    elseif expression.tag == "indexed" then
        if self:is_of_optional_type(expression.variable) then
            error("Type Error: Indexed Access Operator cannot be performed on the value of optional type! In " .. pt(expression))
        end
        if self:is_of_optional_type(expression.index) then
            error("Type Error: Indexed Access Operator cannot accept index of optional type! In " .. pt(expression))
        end
        return false
    elseif expression.tag == "new_array" then
        for i = 1, #expression.array_size do
            if self:is_of_optional_type(expression.array_size[i]) then 
                error("Type Error: New Array Operator cannot have accept operands of optional type! "
                .. "But the size of dimension '" .. tostring(i) .. "' is of optional type! In " .. pt(expression))
            end
        end
        return false
    elseif expression.tag == "binop" then
        if self:is_of_optional_type(expression.left_operand) or self:is_of_optional_type(expression.right_operand) then
            error("Type Error: Binary '" .. expression.operator .. "' cannot accept operands of optional type! In " .. pt(expression))
        end
        return false
    elseif expression.tag == "logical_operator" then
        if self:is_of_optional_type(expression.left_operand) or self:is_of_optional_type(expression.right_operand) then
            error("Type Error: Logical '" .. expression.operator .. "' cannot accept operands of optional type! In " .. pt(expression))
        end
        return false
    elseif expression.tag == "unary_operator" then
        if self:is_of_optional_type(expression.operand) then
            error("Type Error: Unary '" .. expression.operator .. "' cannot accept operand of optional type! In " .. pt(expression))
        end
        return false
    elseif expression.tag == "ternary_operator" then
        if self:is_of_optional_type(expression.condition)
            or self:is_of_optional_type(expression.truthy_expression)
            or self:is_of_optional_type(expression.falsy_expression) then
            error("Type Error: Ternary Operator cannot accept operands of optional type! In " .. pt(expression))
        end
        return false
    elseif expression.tag == "is_present_operator" then
        return false
    elseif expression.tag == "or_else_operator" then
        if not self:is_of_optional_type(expression.left_operand) then
            error("Type Error: Or Else Operator cannot accept non-optional type as its left operand! In " .. pt(expression))
        end
        if self:is_of_optional_type(expression.right_operand) then
            error("Type Error: Or Else Operator cannot accept optional type as its right operand! In " .. pt(expression))
        end
        return false
    else
        error("Cannot perform type inference; Invalid expression tree: " .. pt(expression))
    end
end


function Compiler:verify_no_local_variable_redeclaration_in_current_block(block_base)
    local locals = self.locals
    local parameters = self.parameters.formal
    for i = block_base, #locals do
        for j = 1, #parameters do
            if locals[i].name == parameters[j] then
                error("Compilation Error: Local variable '" .. locals[i].name .. "' in function '"
                    .. self.current_function_name
                        .. "' attempts to redefine the formal parameter with the same name!")
            end
        end

        for j = i + 1, #locals do
            if locals[i].name == locals[j].name then
                error("Compilation Error: Local variable '" .. locals[i].name
                        .. "' has been defined more than once in the same block!")
            end
        end
    end
end

function Compiler:type_check_statement(statement)
    if statement.tag == "assignment" then

        if statement.target.tag == "variable" then
            local local_index, local_is_optional = self:find_local(statement.target.variable_name)
            if local_index then
                if not local_is_optional and self:is_of_optional_type(statement.expression) then
                    error("Type Error: Cannot assign value of optional type to a local varaible of non-optional type! In " .. pt(statement))
                end
            else
                -- valid: can assign anything to global variable
            end
        elseif statement.target.tag == "indexed" then
            if self:is_of_optional_type(statement.expression) then
                error("Type Error: Cannot assign value of optional type to an array element! In " .. pt(statement))
            end

            if self:is_of_optional_type(statement.target.variable) then
                error("Type Error: Indexed Access Operator cannot be performed on the value of optional type! In " .. pt(statement.target))
            end
            if self:is_of_optional_type(statement.target.index) then
                error("Type Error: Indexed Access Operator cannot accept index of optional type! In " .. pt(statement.target))
            end
        else
            error("invalid tree for assignment target: " .. pt(statement))
        end
        
    elseif statement.tag == "local_variable" then
        if (not statement.is_optional)
            and (statement.initial_value and self:is_of_optional_type(statement.initial_value)) then
                error("Type Error: Cannot initialize non-optional variable '"
                    ..statement.name.."' with value of optional type! " .. pt(statement))
        end
    elseif statement.tag == "block" then
        -- do not type check children because it will be done when generating code for them
    elseif statement.tag == "call" then
        self:type_check_call(statement)
    elseif statement.tag == "sequence" then
        -- do not type check children because it will be done when generating code for them
    elseif statement.tag == "if" then
        -- do not type check children because it will be done when generating code for them
        if self:is_of_optional_type(statement.condition) then
            error("Type Error: If-ElseIf-Else Statement cannot accept condition of optional type! " .. pt(statement.condition))
        end
    elseif statement.tag == "while" then
        -- do not type check children because it will be done when generating code for them
        if self:is_of_optional_type(statement.condition) then
                error("Type Error: While Statement cannot accept condition of optional type! " .. pt(statement.condition))
        end
    elseif statement.tag == "return" then
        if not self.current_function_returns_optional and self:is_of_optional_type(statement.expression) then
            error("Type Error: Cannot Return an expression of optional type! Because function '"
                .. self.current_function_name .. "' has not declared optional return! In" .. pt(statement))
        end
    elseif statement.tag == "print" then
        -- always valid
    elseif statement.tag == "skip" then
        -- always valid
    else
        error("invalid tree")
    end
end

function Compiler:generate_code_from_block(block)
    local old_level = #self.locals
    self:generate_code_from_statement(block.body)
    local diff = #self.locals - old_level
    if diff > 0 then
        self:verify_no_local_variable_redeclaration_in_current_block(old_level + 1)
        for i = 1, diff do
            table.remove(self.locals)
        end
        self:add_opcode("pop", diff)
    end
end

function Compiler:generate_code_from_assignment(assignment)
    self:generate_code_from_expression(assignment.expression)
    if assignment.target.tag == "variable" then
        local local_index = self:find_local(assignment.target.variable_name)
        if local_index then
            self:add_opcode("store_local", local_index)
        else
            self:add_opcode("store", self:global_variable_index_from_name(assignment.target.variable_name))
        end
    elseif assignment.target.tag == "indexed" then
        self:generate_code_from_expression(assignment.target.variable)
        self:generate_code_from_expression(assignment.target.index)
        self:add_opcode("array_store")
    else
        error("invalid tree for assignment target")
    end
end

function Compiler:generate_code_from_statement(statement)
    self:type_check_statement(statement)
    if statement.tag == "assignment" then
        self:generate_code_from_assignment(statement)
    elseif statement.tag == "local_variable" then
        local default_initial_value = (statement.is_optional) and ast._null() or ast._number(0) 
        self:generate_code_from_expression(statement.initial_value or default_initial_value)
        self.locals[#self.locals + 1] = { name = statement.name, is_optional = statement.is_optional }
    elseif statement.tag == "block" then
        self:generate_code_from_block(statement)
    elseif statement.tag == "call" then
        self:generate_code_from_call(statement)
        self:add_opcode("pop", 1)
    elseif statement.tag == "sequence" then
        self:generate_code_from_statement(statement.first)
        self:generate_code_from_statement(statement.second)
    elseif statement.tag == "if" then
        self:generate_code_from_expression(statement.condition)
        local jump = self:generate_jump_if_zero()
        self:generate_code_from_statement(statement.if_branch)
        if statement.else_branch == nil then
            self:point_jump_to_here(jump)
        else
            local jump2 = self:generate_jump()
            self:point_jump_to_here(jump)
            self:generate_code_from_statement(statement.else_branch)
            self:point_jump_to_here(jump2)
        end
    elseif statement.tag == "while" then
        local loop_start = self:current_position()
        self:generate_code_from_expression(statement.condition)
        local jump = self:generate_jump_if_zero()
        self:generate_code_from_statement(statement.loop_body)
        self:generate_jump_to(loop_start)
        self:point_jump_to_here(jump)
    elseif statement.tag == "return" then
        self:generate_code_from_expression(statement.expression)
        self:add_opcode("ret", #self.locals + #self.parameters.formal)
    elseif statement.tag == "print" then
        self:generate_code_from_expression(statement.expression)
        self:add_opcode("print")
    elseif statement.tag == "skip" then
        --skip
    else
        error("invalid tree")
    end
end


local function create_function_node_signature(function_node)
    return function_node.name .. "@" .. #function_node.parameters.formal
end

local function create_pretty_function_node_name(function_node)
    return "<'" .. function_node.name .. "' with " .. #function_node.parameters.formal .. " formal parameter(s)>"
end

local function default_parameter_redefinition_happened(old_function_decalaration, new_function_decalaration)
    return (old_function_decalaration.parameters.default and new_function_decalaration.parameters.default)
        and (new_function_decalaration.parameters.default ~= old_function_decalaration.parameters.default)
end

local function return_type_conflict_present(old_function_decalaration, new_function_decalaration)
    return old_function_decalaration.returns_optional ~= new_function_decalaration.returns_optional
end


function Compiler:declare_function(function_node)
    local name = create_pretty_function_node_name(function_node)
    local formal_parameters = function_node.parameters.formal

    for i = 1, #formal_parameters do
        for j = i + 1, #formal_parameters do
            if formal_parameters[i] == formal_parameters[j] then
                error("Compilation Error: Function " .. name .. " contains more than one parameter named '"
                        .. formal_parameters[i] .. "'!")
            end
        end
    end

    local signature = create_function_node_signature(function_node)

    if self.functions[signature] then
        if default_parameter_redefinition_happened(self.functions[signature], function_node) then
            error("Compilation Error: Function " .. name .. " has already been declared with default "
                .. "parameter! There can only be one declaration of a function that specifies the default parameter!")
        end

        if function_node.parameters.default then
            self.functions[signature].parameters.default = function_node.parameters.default
        end

        if return_type_conflict_present(self.functions[signature], function_node) then
            error("Compilation Error: Function " .. name .. " has already been declared with a different return type!"
                .. " Please make sure that return type is consistenet between all declarations!")
        end

        if function_node.parameters.default then
            self.functions[signature].parameters.default = function_node.parameters.default
        end

        return self.functions[signature]
    end

    if self.globals[function_node.name] then
        error("Compilation Error: Function " .. name .. " cannot be declared, \
            \rbecause there already exists a global variable with the same name!")
    end

    self.functions[signature] = {
        name = name,
        parameters = {
            count = #formal_parameters,
            default = function_node.parameters.default,
        },
        returns_optional = function_node.returns_optional,
    }

    return self.functions[signature]
end

function Compiler:compile_function(function_node)

    local call_site = self:declare_function(function_node)
    
    if not function_node.body then return end
    
    if call_site.code then
        error("Compilation Error: Function " .. call_site.name .. " has been defined more than once!")
    end

    call_site.code = {}
    self.code = call_site.code
    self.parameters = function_node.parameters
    self.current_function_name = call_site.name
    self.current_function_returns_optional = call_site.returns_optional

    self:generate_code_from_statement(function_node.body)
    local default_return_value = call_site.returns_optional and ast._null() or ast._number(0)
    self:generate_code_from_statement(ast._return(default_return_value))
end

local function compile(ast, log_level)
    for _, function_node in ipairs(ast) do
        Compiler:declare_function(function_node)
    end
    for _, function_node in ipairs(ast) do
        Compiler:compile_function(function_node)
    end
    for _, call_site in ipairs(Compiler.functions) do
        assert(call_site.code,
                "Compilation Error: function '" .. call_site.name .. "' has been declared but not defined!")
    end
    local main = Compiler:find_overload("main", 0)
    if not main then error("No function 'main' with 0 formal parameters") end

    if log_level and (log_level & log_levels.display_compiled_code ~= 0) then
        print("Compiled Code: " .. pt(main) .. "\n")
    end

    return main
end

return { compile = compile }