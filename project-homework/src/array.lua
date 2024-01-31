local pt = require "pt".pt


local function is_array(value)
    return type(value) == "table" and value.size ~= nil
end


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


local function value_as_string(value, visited_arrays)
    if not is_array(value) then return tostring(value) end

    local array_prefix, array_suffix = "array["..tostring(value.size).."]: { ", " }"
    
    visited_arrays = visited_arrays or {}
    if visited_arrays[value] then return array_prefix .. "..." .. array_suffix end
    visited_arrays[value] = true

    local array_as_string = array_prefix
    for i = 1, value.size - 1 do
        array_as_string = array_as_string .. value_as_string(value[i], visited_arrays) .. ", "
        visited_arrays[value[i]] = nil
    end
    array_as_string = array_as_string .. value_as_string(value[value.size], visited_arrays) .. array_suffix

    return array_as_string
end


local Array = { size = 0 }


function Array:of_size(...)
    local sizes = {...}
    local size = table.remove(sizes, 1)
    verify_array_size(size)

    local array = { size = size }

    self.__index = self
    setmetatable(array, self)

    for i = 1, size do
        array[i] = (#sizes > 0)
            and self:of_size(table.unpack(sizes)) or 0
    end

    return array
end


function Array:get(index)
    verify_array_type_and_index_bounds(self, index)
    return self[index]
end


function Array:put(index, value)
    verify_array_type_and_index_bounds(self, index)
    self[index] = value
end


function Array:__tostring()
    return value_as_string(self)
end


return Array
