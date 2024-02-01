local pt = require "pt".pt

local log_levels = require "loglevels".runner

local Stack = require "stack"
local Array = require "array"

----------------------------------------------------- Interpreter ------------------------------------------------------

------------------------------------ Logger ------------------------------------

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

local function log_intrepreter_start(log_level)
    if log_level & log_levels.everything == 0 then return end
    print("Starting Interpreter...")
end

local function log_intrepreter_state(log_level, cycle, code, pc, stack)
    if log_level & log_levels.trace_every_cycle == 0 then return end
    
    print("Interpreter Cycle: " .. cycle)
    print("\t" .. "PC = " .. tostring(pc))
    print("\t" .. "Stack = " .. tostring(stack))
    print("\t" .. "Current Instruction = " .. instruction_as_string(code, pc))
end

local function log_interpreter_exit(log_level, return_value)
    if log_level & log_levels.everything == 0 then return end
    print("Finished Execution. Returning '" .. tostring(return_value) .. "'", "\n")
end

local function log_function_start(log_level, function_name)
    if log_level & log_levels.trace_function_calls == 0 then return end
    print("Calling function '" .. function_name .. "'...")
end

local function log_function_exit(log_level, function_name)
    if log_level & log_levels.trace_function_calls == 0 then return end
    print("Returning from function '" .. function_name .."'...")
end

------------------------------------ Runner ------------------------------------

local function verify_call_site_can_be_executed(call_site)
    assert(call_site.code,
        "Runtime Error: function " .. call_site.name .. " cannot be executed, because it has no defined function body!")
end

local function call(call_site, memory, stack, log_level, cycle)
    verify_call_site_can_be_executed(call_site)


    log_level = log_level or 0
    cycle = (cycle or 0) + 1

    local code = call_site.code
    local base = stack:size()
    local pc = 1

    log_function_start(log_level, call_site.name)

    while true do
        log_intrepreter_state(log_level, cycle, code, pc, stack)

        local current_instruction = code[pc]

        if current_instruction == "ret" then
            log_function_exit(log_level, call_site.name)

            local return_value = stack:pop()
            stack:drop(code[pc + 1])
            stack:push(return_value)

            return cycle
        elseif current_instruction == "call" then
            pc = pc + 1
            local call_site = code[pc]
            cycle = call(call_site, memory, stack, log_level, cycle)
        elseif current_instruction == "print" then
            print(stack:pop())
        elseif current_instruction == "jump" then
            pc = pc + 1
            pc = pc + code[pc]
        elseif current_instruction == "jump_if_zero" then
            pc = pc + 1
            pc = pc + ((stack:pop() == 0) and code[pc] or 0)
        elseif current_instruction == "jump_if_zero_or_pop" then
            pc = pc + 1
            if stack:peek() == 0 then
                pc = pc + code[pc]
            else
                stack:drop()
            end
        elseif current_instruction == "jump_if_not_zero_or_pop" then
            pc = pc + 1
            if stack:peek() ~= 0 then
                pc = pc + code[pc]
            else
                stack:drop()
            end
        elseif current_instruction == "push" then
            pc = pc + 1
            stack:push(code[pc])
        elseif current_instruction == "pop" then
            pc = pc + 1
            stack:drop(code[pc])
        elseif code[pc] == "load_local" then
            pc = pc + 1
            stack:push(stack[base + code[pc]])
        elseif code[pc] == "load" then
            pc = pc + 1
            -- TODO: might be useful to throw undefined variable exception here
            --       in case the variable is not present in the memory
            -- UPDATE: now that we handle undefined variables at compile time, this is no longer an issue.
            --      BUT, if we separate out compilation and execution stages later on, we will still need
            --           to verify this at runtime.
            -- UPDATE: with introduction of the functions and branches, this check has to live at run-time only
            local value = memory[code[pc]]
            -- assert(value ~= nil, "Runtime Error: Attempt to reference uninitialized variable '" .. code[pc] .. "'!")
            stack:push(value)
        elseif code[pc] == "store_local" then
            pc = pc + 1
            stack[base + code[pc]] = stack:pop()
        elseif code[pc] == "store" then
            pc = pc + 1
            memory[code[pc]] = stack:pop()
        elseif code[pc] == "new_array" then
            pc = pc + 1
            local number_of_dimensions = code[pc]
            stack:push(Array:of_size(stack:pop(number_of_dimensions)))
        elseif code[pc] == "array_load" then
            local array, index = stack:pop(2)
            stack:push(Array.get(array, index, value))
        elseif code[pc] == "array_store" then
            local value, array, index = stack:pop(3)
            Array.put(array, index, value)
        elseif current_instruction == "eq" then
            local left, right = stack:pop(2)
            stack:push((left == right) and 1 or 0)
        elseif current_instruction == "neq" then
            local left, right = stack:pop(2)
            stack:push((left ~= right) and 1 or 0)
        elseif current_instruction == "lte" then
            local left, right = stack:pop(2)
            stack:push((left <= right) and 1 or 0)
        elseif current_instruction == "gte" then
            local left, right = stack:pop(2)
            stack:push((left >= right) and 1 or 0)
        elseif current_instruction == "lt" then
            local left, right = stack:pop(2)
            stack:push((left < right) and 1 or 0)
        elseif current_instruction == "gt" then
            local left, right = stack:pop(2)
            stack:push((left > right) and 1 or 0)
        elseif current_instruction == "not" then
            local operand = stack:pop()
            stack:push((operand == 0) and 1 or 0)
        elseif current_instruction == "add" then
            local left, right = stack:pop(2)
            stack:push(left + right)
        elseif current_instruction == "sub" then
            local left, right = stack:pop(2)
            stack:push(left - right)
        elseif current_instruction == "mul" then
            local left, right = stack:pop(2)
            stack:push(left * right)
        elseif current_instruction == "div" then
            local left, right = stack:pop(2)
            stack:push(left / right)
        elseif current_instruction == "mod" then
            local left, right = stack:pop(2)
            stack:push(left % right)
        elseif current_instruction == "exp" then
            local left, right = stack:pop(2)
            stack:push(left ^ right)
        elseif current_instruction == "negate" then
            stack:push(-stack:pop())
        else
            error("unknown instruction: '" .. current_instruction .. "'")
        end

        -- can only have numbers or arrays on the stack or nil
        assert(stack:size() == 0 or stack:size() > 0
            and (stack:peek() == nil or type(stack:peek()) == "number" or type(stack:peek()) == "table"))

        pc = pc + 1
        cycle = cycle + 1
    end
end

local function run(call_site, log_level)
    local memory = {}
    local stack = Stack:new()
    log_intrepreter_start(log_level)
    call(call_site, memory, stack, log_level)
    local result = stack:pop()
    log_interpreter_exit(log_level, result)
    return result
end

return { run = run }


