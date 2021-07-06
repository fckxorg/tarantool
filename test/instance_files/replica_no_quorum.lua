#!/usr/bin/env tarantool
local SOCKET_DIR = os.getenv('VARDIR')
box.cfg({
    work_dir = os.getenv('TARANTOOL_WORKDIR'),
    listen              = SOCKET_DIR .. '/no_quorum.sock',
    replication = SOCKET_DIR .. '/master.sock',
    memtx_memory        = 107374182,
    replication_connect_quorum = 0,
    replication_timeout = 0.1,
})

_G.ready = true
