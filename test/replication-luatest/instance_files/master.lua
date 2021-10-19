#!/usr/bin/env tarantool

local function instance_uri(instance)
    local port = os.getenv(instance)
    return 'localhost:' .. port
end

box.cfg({
    --log_level         = 7,
    work_dir            = os.getenv('TARANTOOL_WORKDIR'),
    listen              = os.getenv('TARANTOOL_LISTEN'),
    replication         = {
        instance_uri('TARANTOOL_LISTEN'),
        instance_uri('TARANTOOL_REPLICA')
    },
    memtx_memory        = 107374182,
    replication_timeout = 0.1,
    read_only           = false
})

box.schema.user.grant('guest', 'read, write, execute, create', 'universe', nil, {if_not_exists=true})
require('log').warn("master is ready")
