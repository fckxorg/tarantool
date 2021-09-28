#!/usr/bin/env tarantool
local workdir = os.getenv('TARANTOOL_WORKDIR')
local listen = os.getenv('TARANTOOL_LISTEN')

box.cfg({
    work_dir = workdir,
--     listen = 'localhost:3310'
    listen = listen,
    log = workdir..'/tarantool.log',
})

box.schema.user.grant('guest', 'read,write,execute,create', 'universe')

_G.ready = true
