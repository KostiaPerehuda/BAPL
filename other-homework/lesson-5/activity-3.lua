local function node(tag, ...)
    local labels = table.pack(...)
    local params = table.concat(labels, ", ")
    local fields = {}
    for i, v in ipairs(labels) do fields[i] = v.." = "..v end 
    fields = table.concat(fields, ", ")
    local code  = string.format("return function(%s) return {tag = '%s', %s} end", params, tag, fields)
    print(code)
    return load(code)()
end

assignment_node = node("assignment", "assignment_target", "expression")
print(assignment_node)