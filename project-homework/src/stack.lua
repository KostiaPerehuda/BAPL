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


function Stack:__tostring()
    local stack_as_string = "{ Top --> |"
    for i = #self, 1, -1 do stack_as_string = stack_as_string .. tostring(self[i]) .. "|" end
    stack_as_string = stack_as_string .. " <-- Bottom }"
    return stack_as_string
end


return Stack
