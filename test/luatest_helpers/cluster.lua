local t = require('luatest')
local fio = require('fio')
local Process = t.Process
local Server = require('test.luatest_helpers.server')

local root = os.environ()['SOURCEDIR'] or '.'

local DEFAULT_CHECKPOINT_PATTERNS = {"*.snap", "*.xlog", "*.vylog",
                                     "*.inprogress", "[0-9]*/"}

local Cluster = {}

function Cluster:new(object)
    self:inherit(object)
    object:initialize()
    self.servers = object.servers
    self.built_servers = object.built_servers
    return object
end

function Cluster:inherit(object)
    object = object or {}
    setmetatable(object, self)
    self.__index = self
    self.servers = {}
    self.built_servers = {}
    return object
end

function Cluster:initialize()
    self.servers = {}
end

function Cluster:cleanup(path)
    for _, pattern in ipairs(DEFAULT_CHECKPOINT_PATTERNS) do
        fio.rmtree(fio.pathjoin(path, pattern))
    end
end

function Cluster:server(alias)
    for _, server in ipairs(self.servers) do
        if server.alias == alias then
            return server
        end
    end
    return nil
end

function Cluster:drop_cluster(servers)
    for _, server in ipairs(servers) do
        if server ~= nil then
            server:stop()
            self:cleanup(server.workdir)
        end
    end
end

function Cluster:get_index(server)
    local index = nil
    for i, v in ipairs(self.servers) do
        if (v.id == server) then
          index = i
        end
    end
    return index
end

function Cluster:delete_server(server)
    local idx = self:get_index(server)
    if idx == nil then
        print("Key does not exist")
    else
        table.remove(self.servers, idx)
    end
end

function Cluster:stop()
    self:drop_cluster(self.built_servers)
end

function Cluster:start(opts)
    for _, server in ipairs(self.servers) do
        if not server.process then
            server:start({wait_for_readiness = false})
        end
    end

    -- The option is true by default.
    local wait_for_readiness = true
    if opts ~= nil and opts.wait_for_readiness ~= nil then
        wait_for_readiness = opts.wait_for_readiness
    end

    if wait_for_readiness then
        for _, server in ipairs(self.servers) do
            server:wait_for_readiness()
        end
    end
    t.helpers.retrying({timeout = 20},
        function()
            for _, server in ipairs(self.servers) do
                t.assert(Process.is_pid_alive(server.process.pid),
                    ('%s failed on start'):format(server.alias))
                server:connect_net_box()
            end
        end
    )
    for _, server in ipairs(self.servers) do
        t.assert_equals(server.net_box.state, 'active',
            'wrong state for server="%s"', server.alias)
    end
end

function Cluster:build_server(replicaset_config, engine, boxcfg, instance_file)
    instance_file = instance_file or 'default.lua'
    replicaset_config = replicaset_config or {}
    local server_config = {
        alias = replicaset_config.alias,
        command = fio.pathjoin(root, 'test/instances/', instance_file),
        engine = engine,
        box_cfg = boxcfg,
    }
    assert(server_config.alias, 'Either replicaset.alias or server.alias must be given')
    local server = Server:new(server_config)
    table.insert(self.built_servers, server)
    return server
end

function Cluster:join_server(server)
    if self:server(server.alias) ~= nil then
        return
    end
    table.insert(self.servers, server)
end

function Cluster:build_and_join_server(config, replicaset_config, engine)
    local server = self:build_server(config, replicaset_config, engine)
    self:join_server(server)
    return server
end


function Cluster:get_leader()
    for _, replica in ipairs(self.servers) do
        if replica:eval('return box.info.ro') == false then
            return replica
        end
    end
end

function Cluster:box_bootstrap(bootstrap_function)
    local leader = self:get_leader()
    leader:exec(bootstrap_function)
end


return Cluster
