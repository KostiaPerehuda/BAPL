local pt = require "pt".pt


local Stack = {}


function Stack:new(object)
    object = object or {}
    assert(type(object) == "table")

    self.__index = self
    setmetatable(object, self)
    return object
end


function Stack:drop(number_of_values)
    number_of_values = number_of_values or 1
    assert(number_of_values <= #self, "Stack Underflow Error: Not enough elements to drop!")

    for i = 1, number_of_values do table.remove(self) end
end


function Stack:pop(number_of_values)
    number_of_values = number_of_values or 1
    assert(number_of_values <= #self, "Stack Underflow Error: Not enough elements to pop!")

    values = table.move(self, #self - number_of_values + 1, #self, 1, {})
    self:drop(number_of_values)

    return table.unpack(values)
end


function Stack:push(...)
    local new_values = {...}
    table.move(new_values, 1, #new_values, #self + 1, self)
end


function Stack:peek(number_of_values)
    number_of_values = number_of_values or 1
    assert(number_of_values <= #self, "Stack Underflow Error: Not enough elements to peek!")

    if number_of_values == 1 then return self[#self] end
    return table.unpack(table.move(self, #self - number_of_values + 1, #self, 1, {}))
end


function Stack:size()
    return #self
end


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


function Stack:__tostring()
    local stack_as_string = "{ Top --> |"
    for i = #self, 1, -1 do stack_as_string = stack_as_string .. value_as_string(self[i]) .. "|" end
    stack_as_string = stack_as_string .. " <-- Bottom }"
    return stack_as_string
end


return Stack
