local t = require('luatest')
local log = require('log')
local fiber = require('fiber')
local Cluster =  require('test.luatest_helpers.cluster')

local pg = t.group('quorum_master', {{engine = 'memtx'}, {engine = 'vinyl'}})

pg.before_each(function(cg)
    local engine = cg.params.engine
    cg.cluster = Cluster:new({})
    cg.master_quorum1 = cg.cluster:build_server(
        {args = {'0.1'},}, {alias = 'master_quorum1', },
        'master_quorum.lua', engine)
    cg.master_quorum2 = cg.cluster:build_server(
        {args = {'0.1'},}, {alias = 'master_quorum2', },
        'master_quorum.lua', engine)

    pcall(log.cfg, {level = 6})

end)

pg.after_each(function(cg)
    cg.cluster.servers = nil
    cg.cluster:stop()
end)

pg.before_test('test_master_master_works', function(cg)
    cg.cluster:join_server(cg.master_quorum1)
    cg.cluster:join_server(cg.master_quorum2)
end)

pg.after_test('test_master_master_works', function(cg)
    cg.cluster:drop_cluster({cg.master_quorum1, cg.master_quorum2})
end)

pg.test_master_master_works = function(cg)
    cg.master_quorum1:start()
    cg.master_quorum2:start()

    cg.master_quorum1:eval('repl = box.cfg.replication')
    cg.master_quorum1:eval('box.cfg{replication = ""}')
    t.assert_equals(
        cg.master_quorum1:eval('return box.space.test:insert{1}'), {1})
    cg.master_quorum1:eval('box.cfg{replication = repl}')
    local vclock = cg.master_quorum1:eval('return box.info.vclock')
    fiber.sleep(vclock[1])
    t.assert_equals(
        cg.master_quorum2:eval('return box.space.test:select()'), {{1}})
end
