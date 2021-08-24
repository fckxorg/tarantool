local fio = require('fio')
local log = require('log')

local t = require('luatest')
local g = t.group()

local Server = t.Server

g.before_all(function()
    g.master = Server:new({
        alias = 'master',
        command = './test/replication-luatest/instance_files/master.lua',
        workdir = fio.tempdir(),
        env = {TARANTOOL_REPLICA = '13302'},
        net_box_port = 13301,
    })

    g.replica = Server:new({
        alias = 'replica',
        command = './test/replication-luatest/instance_files/replica.lua',
        workdir = fio.tempdir(),
        env = {TARANTOOL_MASTER = '13301'},
        net_box_port = 13302,
    })


    g.master:start()
    g.replica:start()

    t.helpers.retrying({}, function() g.master:connect_net_box() end)
    t.helpers.retrying({}, function() g.replica:connect_net_box() end)

    log.info('Everything is started')
end)

g.after_all(function()
    g.replica:stop()
    g.master:stop()
    fio.rmtree(g.master.workdir)
    fio.rmtree(g.replica.workdir)
end)

g.test_truncate_is_local_transaction = function()
    g.master:eval("s = box.schema.space.create('temp', {temporary = true})")
    g.master:eval("s:create_index('pk')")

    g.master:eval("s:insert{1, 2}")
    g.master:eval("s:insert{4}")
    t.assert_equals(g.master:eval("return s:select()"), {{1, 2}, {4}})

    g.master:eval("box.begin() box.space._schema:replace{'smth'} s:truncate() box.commit()")
    t.assert_equals(g.master:eval("return s:select()"), {})
    t.assert_equals(g.master:eval("return box.space._schema:select{'smth'}"), {{'smth'}})

    -- Checking that replica has received the last transaction,
    -- and that replication isn't broken.
    t.assert_equals(g.replica:eval("return box.space._schema:select{'smth'}"), {{'smth'}})
    t.assert_equals(g.replica:eval("return box.info.replication[1].upstream.status"), 'follow')
end
