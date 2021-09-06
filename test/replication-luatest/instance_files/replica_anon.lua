#!/usr/bin/env tarantool

local function instance_uri(instance)
    local port = os.getenv(instance)
    return 'localhost:' .. port
end

box.cfg({
    work_dir            = os.getenv('TARANTOOL_WORKDIR'),
    listen              = os.getenv('TARANTOOL_LISTEN'),
    replication         = {
        instance_uri('TARANTOOL_MASTER'),
        instance_uri('TARANTOOL_LISTEN')
    },
    memtx_memory        = 107374182,
    replication_timeout = 0.1,
    replication_connect_timeout = 0.5,
    read_only           = true,
    replication_anon    = true
})

require('log').warn("replica is ready")
