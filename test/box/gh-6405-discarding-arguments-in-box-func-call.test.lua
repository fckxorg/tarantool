args_type = function(...)                     \
    local type_table = {}                     \
    for i = 1, select('#', ...) do            \
        type_table[i] = type(select(i, ...))  \
    end                                       \
    return type_table                         \
end                                           \

box.schema.func.create('args_type')

box_call = box.func.args_type:call({1, nil, 3})
lua_call = args_type(1, nil, 3)
assert(table.equals(box_call, lua_call))
box_call = box.func.args_type:call({'string', nil, 3})
lua_call = args_type('string', nil, 3)
assert(table.equals(box_call, lua_call))
box_call = box.func.args_type:call({1, nil, 7, nil, 3, 5, nil, 9, 10})
lua_call = args_type(1, nil, 7, nil, 3, 5, nil, 9, 10)
assert(table.equals(box_call, lua_call))
box_call = box.func.args_type:call({1, 2, 3, 'string'})
lua_call = args_type(1, 2, 3, 'string')
assert(table.equals(box_call, lua_call))
box_call = box.func.args_type:call({nil, nil, 3})
lua_call = args_type(nil, nil, 3)
assert(table.equals(box_call, lua_call))

box.schema.func.drop('args_type')
