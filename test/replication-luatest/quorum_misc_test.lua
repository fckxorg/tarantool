local t = require('luatest')
local log = require('log')
local fio = require('fio')
local fiber = require('fiber')
local Cluster =  require('test.luatest_helpers.cluster')
local test_checks = require('test.luatest_helpers.checks')
local COUNT = 100

local pg = t.group('quorum_misc', {{engine = 'memtx'}, {engine = 'vinyl'}})

pg.before_each(function(cg)
    local engine = cg.params.engine
    cg.cluster = Cluster:new({})
    cg.quorum1 = cg.cluster:build_server(
        {args = {'0.1'},}, {alias = 'quorum1', }, 'quorum.lua', engine)
    cg.quorum2 = cg.cluster:build_server(
        {args = {'0.1'},}, {alias = 'quorum2', }, 'quorum.lua', engine)
    cg.quorum3 = cg.cluster:build_server(
        {args = {'0.1'},}, {alias = 'quorum3', }, 'quorum.lua', engine)
    cg.replica_quorum = cg.cluster:build_server(
        {args = {'1', '0.05', '10'}}, {alias = 'replica_quorum'}, 'replica_quorum.lua', engine)

    pcall(log.cfg, {level = 6})

end)

pg.after_each(function(cg)
    cg.cluster.servers = nil
    cg.cluster:stop()
end)

pg.before_test('test_quorum_during_reconfiguration', function(cg)
    cg.cluster:join_server(cg.replica_quorum)
end)

pg.after_test('test_quorum_during_reconfiguration', function(cg)
    cg.cluster:drop_cluster({cg.replica_quorum})
end)

pg.test_quorum_during_reconfiguration = function(cg)
    -- Test that quorum is not ignored neither during bootstrap, nor
    -- during reconfiguration.

    fiber.sleep(2)
    cg.replica_quorum:start()
    t.helpers.retrying({timeout = 10},
        function()
            -- If replication_connect_quorum was ignored here, the instance
            -- would exit with an error.
            local cmd = 'return box.cfg{replication = {' ..
                'os.getenv("TARANTOOL_LISTEN"), nonexistent_uri(1)}}'
            -- XXX: box.cfg() returns nothing in either way, I don't see a
            -- point to check it. box.cfg() may raise an error: will it be
            -- re-raised here?
            t.assert_equals(cg.replica_quorum:eval(cmd), nil)
        end
    )

    t.assert_equals(cg.replica_quorum:eval('return box.info.id'), 1)
end


pg.before_test('test_id_for_rebootstrapped_replica_with_removed_xlog',
function(cg)

    cg.cluster:join_server(cg.quorum1)
    cg.cluster:join_server(cg.quorum2)
    cg.cluster:join_server(cg.quorum3)
    cg.cluster:start({wait_for_readiness = false})
    test_checks:check_follow_all_master({cg.quorum1, cg.quorum2, cg.quorum3})
    t.helpers.retrying({timeout = 10},
        function()
            cg.quorum2:eval(
                'for i = 1, ' .. COUNT .. ' do box.space.test:insert{i} end')
        end
    )

end)

pg.test_id_for_rebootstrapped_replica_with_removed_xlog = function(cg)
    cg.quorum1:stop()
    cg.cluster:cleanup(cg.quorum1.workdir)
    fio.rmtree(cg.quorum1.workdir)
    fio.mktree(cg.quorum1.workdir)
    -- The rebootstrapped replica will be assigned id = 4,
    -- because ids 1..3 are busy.
    cg.quorum1.args = {'0.1'}
    cg.quorum1:start()
    t.assert_equals(cg.quorum1.net_box.state, 'active',
        'wrong state for server="%s"', cg.quorum1.alias)
    t.helpers.retrying({timeout = 10}, function()
        t.assert_equals(
            cg.quorum1:eval('return box.space.test:count()'), COUNT)
        t.assert_equals(
            cg.quorum2:eval(
                'return box.info.replication[4].upstream.status'), 'follow')
        t.assert(cg.quorum3:eval('return box.info.replication ~= nil'))
        t.assert_equals(
            cg.quorum3:eval(
                'return box.info.replication[4].upstream.status'), 'follow')
    end)

    t.assert_equals(
        cg.quorum2:eval('return box.info.replication[4].upstream.status'),
        'follow')
    t.assert_equals(
        cg.quorum3:eval('return box.info.replication[4].upstream.status'),
        'follow')
end
