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
    number_node = number_node,
}
