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

function checks:check_follow_server_status(server, ind)
    local status = server:eval(
        ('return box.info.replication[%d].upstream.status'):format(ind))
    t.assert_equals(status, 'follow',
        ('%s: this server does not follow others.'):format(server.alias))
end

function checks:check_follow_all_master(servers)
    for i = 1, #servers do
        if servers[i]:eval('return box.info.id') ~= i then
            t.helpers.retrying({timeout = 20}, function()
                self:check_follow_server_status(servers[i], i)
            end)
        end
    end
end

return checks
