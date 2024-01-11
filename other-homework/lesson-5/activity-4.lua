local pt = require "pt".pt

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

assignment_node = node("assignment", "assignment_target", "expression")("hello", "world")
print(pt(assignment_node))
