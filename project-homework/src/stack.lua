local pt = require "pt".pt


local Stack = { top = 0 }


function Stack:new(object)
    object = object or {}
    assert(type(object) == "table")

    self.__index = self
    setmetatable(object, self)
    return object
end


function Stack:drop(number_of_values)
    number_of_values = number_of_values or 1
    assert(number_of_values <= self:size(), "Stack Underflow Error: Not enough elements to drop!")

    for i = 1, number_of_values do table.remove(self) end
    self.top = self.top - number_of_values
end


function Stack:pop(number_of_values)
    number_of_values = number_of_values or 1
    assert(number_of_values <= self:size(), "Stack Underflow Error: Not enough elements to pop!")

    values = table.move(self, self:size() - number_of_values + 1, self:size(), 1, {})
    self:drop(number_of_values)

    return table.unpack(values)
end


function Stack:push(...)
    local new_values = {...}
    table.move(new_values, 1, #new_values, self:size() + 1, self)
    self.top = self.top + #new_values
end


function Stack:peek(number_of_values)
    number_of_values = number_of_values or 1
    assert(number_of_values <= self:size(), "Stack Underflow Error: Not enough elements to peek!")

    if number_of_values == 1 then return self[self:size()] end
    return table.unpack(table.move(self, self:size() - number_of_values + 1, self:size(), 1, {}))
end


function Stack:size()
    return self.top
end


function Stack:__tostring()
    local stack_as_string = "{ Top --> |"
    for i = self:size(), 1, -1 do stack_as_string = stack_as_string .. tostring(self[i]) .. "|" end
    stack_as_string = stack_as_string .. " <-- Bottom }"
    return stack_as_string
end


return Stack
