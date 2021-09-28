#!/usr/bin/env tarantool
local workdir = os.getenv('TARANTOOL_WORKDIR')
local listen = os.getenv('TARANTOOL_LISTEN')
local SOCKET_DIR = os.getenv('VARDIR')
local MASTER = arg[1] or "master"

local function master_uri()
    return SOCKET_DIR..'/'..MASTER..'.sock'
end

box.cfg({
    work_dir = workdir,
    listen = listen,
    replication = master_uri(),
})

_G.ready = true
