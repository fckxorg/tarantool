local t = require('luatest')

local checks = {}

function checks:new(object)
    self:inherit(object)
    object:initialize()
    return object
end

function checks:inherit(object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    return object
end

function checks:check_follow_all_master(servers)
    for i = 1, #servers do
        if servers[i]:eval('return box.info.id') ~= i then
            t.helpers.retrying({timeout = 20}, function()
               t.assert_equals(servers[i]:eval(
                   'return box.info.replication[' .. i .. '].upstream.status'),
                   'follow',
                   servers[i].alias .. ': this server does not follow others.')
            end)
        end
    end
end

return checks
