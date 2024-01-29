local pt = require "pt".pt

----------------------------------------------------- Interpreter ------------------------------------------------------

local function is_array(value)
    return type(value) == "table" and value.size ~= nil
end

local function value_as_string(value, visited_arrays)
    if not is_array(value) then return tostring(value) end

    local array_prefix = "array["..tostring(value.size).."]: { "
    local array_suffix = " }"
    
    visited_arrays = visited_arrays or {}
    if visited_arrays[value] then return array_prefix .. "..." .. array_suffix end
    visited_arrays[value] = true

    if value.size == 1 then return array_prefix .. value_as_string(value[1], visited_arrays) .. array_suffix end

    local array_as_string = array_prefix
    for i = 1, value.size - 1 do
        array_as_string = array_as_string .. value_as_string(value[i], visited_arrays) .. ", "
    end
    array_as_string = array_as_string .. value_as_string(value[value.size], visited_arrays) .. array_suffix

    return array_as_string
end

local function stack_as_string(stack, stack_top)
    local stack_as_string = "{ Top --> |"
    for i = stack_top, 1, -1 do stack_as_string = stack_as_string .. value_as_string(stack[i]) .. "|" end
    stack_as_string = stack_as_string .. " <-- Bottom }"
    return stack_as_string
end

local function instruction_as_string(code, instruction_pointer)
    local instruction = code[instruction_pointer]
    if instruction == "push" then
        instruction = instruction .. " " .. tostring(code[instruction_pointer + 1])
    elseif instruction == "load" or instruction == "store" then
        instruction = instruction .. " '" .. code[instruction_pointer + 1] .. "'"
    elseif instruction == "call" then
        instruction = instruction .. " '" .. code[instruction_pointer + 1].name .. "'"
    end
    instruction = "{ " .. instruction .. " }"
    return instruction
end

------------------------------------ Logger ------------------------------------

local function log_intrepreter_start(trace_enabled)
    if not trace_enabled then return end
    print("Starting Interpreter...")
end

local function log_intrepreter_state(trace_enabled, cycle, code, pc, stack, stack_top)
    if not trace_enabled then return end
    
    print("Interpreter Cycle: " .. cycle)
    print("\t" .. "PC = " .. tostring(pc))
    print("\t" .. "Stack = " .. stack_as_string(stack, stack_top))
    print("\t" .. "Current Instruction = " .. instruction_as_string(code, pc))
end

local function log_interpreter_exit(trace_enabled, return_value)
    if not trace_enabled then return end
    print("Finished Execution. Returning '" .. value_as_string(return_value) .."'")
end

local function log_function_start(trace_enabled, function_name)
    if not trace_enabled then return end
    print("Calling function '" .. function_name .. "'...")
end

local function log_function_exit(trace_enabled, function_name)
    if not trace_enabled then return end
    print("Returning from function '" .. function_name .."'...")
end

------------------------------------ Runner ------------------------------------

local function verify_array_size(size)
    assert(math.type(size) == "integer" and size >= 1,
        "ArrayCreationError: an array size must be a positive integer, but got '" .. size .. "'!")
end

local function verify_array_type_and_index_bounds(array, index)
    assert(is_array(array),
        "ArrayAccessError: cannot perform array access on a non-array type!")
    assert(math.type(index) == "integer",
        "ArrayAccessError: a non-integer value '".. index .."' cannot be used as an array index!")
    assert(index >= 1 and index <= array.size,
        "ArrayAccessError: index '".. index .. "' is out of bounds of array of size " .. array.size .. "!")
end

local function drop(stack, top, number_of_values)
    for i = top - number_of_values + 1, top do stack[i] = nil end
    return top - number_of_values
end

local function allocate_new_array(sizes, start_at_size)
    local start_at_size = start_at_size or 1
    local size = sizes[start_at_size]
    verify_array_size(size)

    local array = { size = size }
    for i = 1, size do
        array[i] = (start_at_size ~= #sizes)
            and allocate_new_array(sizes, start_at_size + 1) or 0
    end
    return array
end

local function verify_call_site_can_be_executed(call_site)
    assert(call_site.code,
        "Runtime Error: function  '" .. call_site.name .. "' cannot be executed, as it has no associated code!")
end

local function run(call_site, memory, stack, top, trace_enabled, cycle)
    verify_call_site_can_be_executed(call_site)


    trace_enabled = trace_enabled or false
    cycle = (cycle or 0) + 1

    local code = call_site.code
    local base = top
    local pc = 1

    log_function_start(trace_enabled, call_site.name)

    while true do
        log_intrepreter_state(trace_enabled, cycle, code, pc, stack, top)

        local current_instruction = code[pc]

        if current_instruction == "ret" then
            log_function_exit(trace_enabled, call_site.name)

            local n = code[pc + 1]
            stack[top - n] = stack[top]
            top = drop(stack, top, n)

            return top, cycle
        elseif current_instruction == "call" then
            pc = pc + 1
            local call_site = code[pc]
            top, cycle = run(call_site, memory, stack, top, trace_enabled, cycle)
        elseif current_instruction == "print" then
            print(value_as_string(stack[top]))
            top = drop(stack, top, 1)
        elseif current_instruction == "jump" then
            pc = pc + 1
            pc = pc + code[pc]
        elseif current_instruction == "jump_if_zero" then
            pc = pc + 1
            pc = pc + ((stack[top] == 0) and code[pc] or 0)
            top = drop(stack, top, 1)
        elseif current_instruction == "jump_if_zero_or_pop" then
            pc = pc + 1
            if stack[top] == 0 then
                pc = pc + code[pc]
            else
                top = drop(stack, top, 1)
            end
        elseif current_instruction == "jump_if_not_zero_or_pop" then
            pc = pc + 1
            if stack[top] ~= 0 then
                pc = pc + code[pc]
            else
                top = drop(stack, top, 1)
            end
        elseif current_instruction == "push" then
            pc = pc + 1
            top = top + 1
            stack[top] = code[pc]
        elseif current_instruction == "pop" then
            pc = pc + 1
            top = drop(stack, top, code[pc])
        elseif code[pc] == "load_local" then
            pc = pc + 1
            top = top + 1
            stack[top] = stack[base + code[pc]]
        elseif code[pc] == "load" then
            pc = pc + 1
            top = top + 1
            -- TODO: might be useful to throw undefined variable exception here
            --       in case the variable is not present in the memory
            -- UPDATE: now that we handle undefined variables at compile time, this is no longer an issue.
            --      BUT, if we separate out compilation and execution stages later on, we will still need
            --           to verify this at runtime.
            -- UPDATE: with introduction of the functions and branches, this check has to live at run-time only
            stack[top] = memory[code[pc]]
            assert(stack[top] ~= nil, "Runtime Error: Attempt to reference uninitialized variable '" .. code[pc] .. "'!")
        elseif code[pc] == "store_local" then
            pc = pc + 1
            stack[base + code[pc]] = stack[top]
            top = drop(stack, top, 1)
        elseif code[pc] == "store" then
            pc = pc + 1
            memory[code[pc]] = stack[top]
            top = drop(stack, top, 1)
        elseif code[pc] == "new_array" then
            pc = pc + 1
            local number_of_dimensions = code[pc]
            local sizes = table.move(stack, top - number_of_dimensions + 1, top, 1, {})
            top = drop(stack, top, number_of_dimensions - 1)
            stack[top] = allocate_new_array(sizes)
        elseif code[pc] == "array_load" then
            local array = stack[top - 1]
            local index = stack[top]
            verify_array_type_and_index_bounds(array, index)
            stack[top - 1] = array[index]
            top = drop(stack, top, 1)
        elseif code[pc] == "array_store" then
            local value = stack[top - 2]
            local array = stack[top - 1]
            local index = stack[top]
            verify_array_type_and_index_bounds(array, index)
            array[index] = value
            top = drop(stack, top, 3)
        elseif current_instruction == "eq" then
            stack[top - 1] = (stack[top - 1] == stack[top]) and 1 or 0
            top = drop(stack, top, 1)
        elseif current_instruction == "neq" then
            stack[top - 1] = (stack[top - 1] ~= stack[top]) and 1 or 0
            top = drop(stack, top, 1)
        elseif current_instruction == "lte" then
            stack[top - 1] = (stack[top - 1] <= stack[top]) and 1 or 0
            top = drop(stack, top, 1)
        elseif current_instruction == "gte" then
            stack[top - 1] = (stack[top - 1] >= stack[top]) and 1 or 0
            top = drop(stack, top, 1)
        elseif current_instruction == "lt" then
            stack[top - 1] = (stack[top - 1] < stack[top]) and 1 or 0
            top = drop(stack, top, 1)
        elseif current_instruction == "gt" then
            stack[top - 1] = (stack[top - 1] > stack[top]) and 1 or 0
            top = drop(stack, top, 1)
        elseif current_instruction == "not" then
            stack[top] = (stack[top] == 0) and 1 or 0
        elseif current_instruction == "add" then
            stack[top - 1] = stack[top - 1] + stack[top]
            top = drop(stack, top, 1)
        elseif current_instruction == "sub" then
            stack[top - 1] = stack[top - 1] - stack[top]
            top = drop(stack, top, 1)
        elseif current_instruction == "mul" then
            stack[top - 1] = stack[top - 1] * stack[top]
            top = drop(stack, top, 1)
        elseif current_instruction == "div" then
            stack[top - 1] = stack[top - 1] / stack[top]
            top = drop(stack, top, 1)
        elseif current_instruction == "mod" then
            stack[top - 1] = stack[top - 1] % stack[top]
            top = drop(stack, top, 1)
        elseif current_instruction == "exp" then
            stack[top - 1] = stack[top - 1] ^ stack[top]
            top = drop(stack, top, 1)
        elseif current_instruction == "negate" then
            stack[top] = -stack[top]
        else
            error("unknown instruction: '" .. current_instruction .. "'")
        end

        -- can only have numbers or arrays on the stack
        assert(top == 0 or top > 0 and (type(stack[top]) == "number" or type(stack[top]) == "table"))

        pc = pc + 1
        cycle = cycle + 1
    end
end

local function execute(call_site, trace_enabled)
    local memory = {}
    local stack = {}
    local stack_top = 0
    log_intrepreter_start(trace_enabled)
    stack_top = run(call_site, memory, stack, stack_top, trace_enabled)
    local result = stack[stack_top]
    log_interpreter_exit(trace_enabled, result)
    return result
end

return { run = execute }


