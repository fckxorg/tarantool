env = require('test_run')
net_box = require('net.box')
json = require('json')
fiber = require('fiber')
test_run = env.new()

test_run:cmd("create server test with script='box/gh-5860-implement-streams.lua'")

test_run:cmd("setopt delimiter ';'")
function get_current_connection_count()
    local total_net_stat_table = test_run:cmd(string.format("eval test 'return box.stat.net()'"))[1]
    assert(total_net_stat_table)
    local connection_stat_table = total_net_stat_table["CONNECTIONS"]
    assert(connection_stat_table)
    return connection_stat_table["current"]
end;
function wait_zero_connection_count(timeout)
    local default_timeout = 2
    local time_before = fiber.time64()
    local microsec_per_sec = 1000000
    timeout = timeout or 2
    while get_current_connection_count() ~= 0 do
        fiber.sleep(0.1)
        if fiber.time64() - time_before > timeout * microsec_per_sec then
            return false
        end
    end
    return true
end;
test_run:cmd("setopt delimiter ''");

-- Some simple checks for new object - stream
test_run:cmd("start server test with args='1'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]
-- User can use automatically generated stream_id or sets it
-- manually, not mix this.
conn = net_box.connect(server_addr)
stream = conn:stream()
-- Error unable to mix user and automatically generated stream_id
-- for one connection.
_ = conn:stream(1)
conn:close()
conn = net_box.connect(server_addr)
stream = conn:stream(1)
-- Error unable to mix user and automatically generated stream_id
-- for one connection.
_ = conn:stream()
conn:close()
-- For different connections it's ok
conn_1 = net_box.connect(server_addr)
stream_1 = conn_1:stream(1)
conn_2 = net_box.connect(server_addr)
stream_2 = conn_2:stream()
-- Stream is a wrapper around connection, so if you close connection
-- you close stream, and vice versa.
conn_1:close()
assert(not stream_1:ping())
stream_2:close()
assert(not conn_2:ping())
-- Simple checks for transactions
conn_1 = net_box.connect(server_addr)
conn_2 = net_box.connect(server_addr)
stream_1_1 = conn_1:stream(1)
stream_1_2 = conn_1:stream(2)
-- It's ok to have streams with same id for different connections
stream_2 = conn_2:stream(1)
-- It's ok to commit or rollback without any active transaction
stream_1_1:commit()
stream_1_1:rollback()

stream_1_1:begin()
-- Error unable to start second transaction in one stream
stream_1_1:begin()
-- It's ok to start transaction in separate stream in one connection
stream_1_2:begin()
-- It's ok to start transaction in separate stream in other connection
stream_2:begin()
test_run:cmd("switch test")
-- It's ok to start local transaction separately with active stream
-- transactions
box.begin()
box.commit()
test_run:cmd("switch default")
stream_1_1:commit()
stream_1_2:commit()
stream_2:commit()

--Check that spaces in stream object updates, during reload_schema
conn = net_box.connect(server_addr)
stream = conn:stream()
test_run:cmd("switch test")
-- Create one space on server
s = box.schema.space.create('test', { engine = 'memtx' })
_ = s:create_index('primary')
test_run:cmd("switch default")
assert(not conn.space.test)
assert(not stream.space.test)
conn:reload_schema()
assert(conn.space.test ~= nil)
assert(stream.space.test ~= nil)
test_run:cmd("switch test")
s:drop()
test_run:cmd("switch default")
conn:reload_schema()
assert(not conn.space.test)
assert(not stream.space.test)

test_run:cmd("stop server test")

-- All test works with iproto_thread count = 10

-- Second argument (false is a value for memtx_use_mvcc_engine option)
-- Server start without active transaction manager, so all transaction
-- fails because of yeild!
test_run:cmd("start server test with args='10, false'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]

test_run:cmd("switch test")
s = box.schema.space.create('test', { engine = 'memtx' })
_ = s:create_index('primary')
test_run:cmd('switch default')

conn = net_box.connect(server_addr)
assert(conn:ping())
stream = conn:stream()
space = stream.space.test

-- Check syncronious stream txn requests for memtx
-- with memtx_use_mvcc_engine = false
stream:begin()
test_run:cmd('switch test')
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 1)
test_run:cmd('switch default')
space:replace({1})
-- Empty select, transaction was not commited and
-- is not visible from requests not belonging to the
-- transaction.
space:select{}
-- Select is empty, because memtx_use_mvcc_engine is false
space:select({})
test_run:cmd("switch test")
-- Select is empty, transaction was not commited
s:select()
test_run:cmd('switch default')
-- Commit fails, transaction yeild with memtx_use_mvcc_engine = false
stream:commit()
-- Select is empty, transaction was aborted
space:select{}
-- Check that after failed transaction commit we able to start next
-- transaction (it's strange check, but it's necessary because it was
-- bug with it)
stream:begin()
stream:ping()
stream:commit()
test_run:cmd('switch test')
s:drop()
-- Check that there are no streams and messages, which
-- was not deleted
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0)
assert(errinj.get('ERRINJ_IPROTO_STREAMS_MSG_COUNT') == 0)
test_run:cmd('switch default')
stream:close()
assert(wait_zero_connection_count())
test_run:cmd("stop server test")

-- Next we check transactions only for memtx with
-- memtx_use_mvcc_engine = true and for vinyl, because
-- if memtx_use_mvcc_engine = false all transactions fails,
-- as we can see before!

-- Second argument (true is a value for memtx_use_mvcc_engine option)
-- Same test case as previous but server start with active transaction
-- manager. Also check vinyl, because it's behaviour is same.
test_run:cmd("start server test with args='10, true'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]

test_run:cmd("switch test")
s1 = box.schema.space.create('test_1', { engine = 'memtx' })
s2 = box.schema.space.create('test_2', { engine = 'vinyl' })
_ = s1:create_index('primary')
_ = s2:create_index('primary')
test_run:cmd('switch default')

conn = net_box.connect(server_addr)
assert(conn:ping())
stream_1 = conn:stream()
stream_2 = conn:stream()
space_1 = stream_1.space.test_1
space_2 = stream_2.space.test_2
-- Spaces getting from connection, not from stream has no stream_id
-- and not belongs to stream
space_1_no_stream = conn.space.test_1
space_2_no_stream = conn.space.test_2
-- Check syncronious stream txn requests for memtx
-- with memtx_use_mvcc_engine = true and to vinyl:
-- behaviour is same!
stream_1:begin()
space_1:replace({1})
stream_2:begin()
space_2:replace({1})
test_run:cmd('switch test')
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 2)
test_run:cmd('switch default')
-- Empty select, transaction was not commited and
-- is not visible from requests not belonging to the
-- transaction.
space_1_no_stream:select{}
space_2_no_stream:select{}
-- Select return tuple, which was previously inserted,
-- because this select belongs to transaction.
space_1:select({})
space_2:select({})
test_run:cmd("switch test")
-- Select is empty, transaction was not commited
s1:select()
s2:select()
test_run:cmd('switch default')
-- Commit was successful, transaction can yeild with
-- memtx_use_mvcc_engine = true. Vinyl transactions
-- can yeild also.
stream_1:commit()
stream_2:commit()
test_run:cmd("switch test")
-- Check that there are no streams and messages, which
-- was not deleted after commit
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0)
assert(errinj.get('ERRINJ_IPROTO_STREAMS_MSG_COUNT') == 0)
test_run:cmd("switch default")

-- Select return tuple, which was previously inserted,
-- because transaction was successful
space_1:select{}
space_2:select{}
test_run:cmd("switch test")
-- Select return tuple, which was previously inserted,
-- because transaction was successful
s1:select()
s2:select()
s1:drop()
s2:drop()
test_run:cmd('switch default')
conn:close()
assert(wait_zero_connection_count())
test_run:cmd("stop server test")

-- Check conflict resolution in stream transactions,
test_run:cmd("start server test with args='10, true'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]

test_run:cmd("switch test")
s1 = box.schema.space.create('test_1', { engine = 'memtx' })
_ = s1:create_index('primary')
s2 = box.schema.space.create('test_2', { engine = 'vinyl' })
_ = s2:create_index('primary')
test_run:cmd('switch default')

conn = net_box.connect(server_addr)
stream_1 = conn:stream()
stream_2 = conn:stream()
space_1_1 = stream_1.space.test_1
space_1_2 = stream_2.space.test_1
space_2_1 = stream_1.space.test_2
space_2_2 = stream_2.space.test_2
stream_1:begin()
stream_2:begin()

-- Simple read/write conflict.
space_1_1:select({1})
space_1_2:select({1})
space_1_1:replace({1, 1})
space_1_2:replace({1, 2})
stream_1:commit()
-- This transaction fails, because of conflict
stream_2:commit()
test_run:cmd("switch test")
-- Check that there are no streams and messages, which
-- was not deleted after commit
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0)
assert(errinj.get('ERRINJ_IPROTO_STREAMS_MSG_COUNT') == 0)
test_run:cmd("switch default")
-- Here we must accept [1, 1]
space_1_1:select({})
space_1_2:select({})

-- Same test for vinyl sapce
stream_1:begin()
stream_2:begin()
space_2_1:select({1})
space_2_2:select({1})
space_2_1:replace({1, 1})
space_2_2:replace({1, 2})
stream_1:commit()
-- This transaction fails, because of conflict
stream_2:commit()
test_run:cmd("switch test")
-- Check that there are no streams and messages, which
-- was not deleted after commit
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0)
assert(errinj.get('ERRINJ_IPROTO_STREAMS_MSG_COUNT') == 0)
test_run:cmd("switch default")
-- Here we must accept [1, 1]
space_2_1:select({})
space_2_2:select({})

test_run:cmd('switch test')
-- Both select return tuple [1, 1], transaction commited
s1:select()
s2:select()
s1:drop()
s2:drop()
test_run:cmd('switch default')
conn:close()
assert(wait_zero_connection_count())
test_run:cmd("stop server test")

-- Check rollback as a command for memtx and vinyl spaces
test_run:cmd("start server test with args='10, true'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]

test_run:cmd("switch test")
s1 = box.schema.space.create('test_1', { engine = 'memtx' })
_ = s1:create_index('primary')
s2 = box.schema.space.create('test_2', { engine = 'vinyl' })
_ = s2:create_index('primary')
test_run:cmd('switch default')

conn = net_box.connect(server_addr)
stream_1 = conn:stream()
stream_2 = conn:stream()
space_1 = stream_1.space.test_1
space_2 = stream_2.space.test_2
stream_1:begin()
stream_2:begin()

-- Test rollback for memtx space
space_1:replace({1})
-- Select return tuple, which was previously inserted,
-- because this select belongs to transaction.
space_1:select({})
stream_1:rollback()
-- Select is empty, transaction rollback
space_1:select({})

-- Test rollback for vinyl space
space_2:replace({1})
-- Select return tuple, which was previously inserted,
-- because this select belongs to transaction.
space_2:select({})
stream_2:rollback()
-- Select is empty, transaction rollback
space_2:select({})

test_run:cmd("switch test")
-- Check that there are no streams and messages, which
-- was not deleted after rollback
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0)
assert(errinj.get('ERRINJ_IPROTO_STREAMS_MSG_COUNT') == 0)
test_run:cmd("switch default")

-- This is simple test is necessary because i have a bug
-- with halting stream after rollback
stream_1:begin()
stream_1:commit()
stream_2:begin()
stream_2:commit()
conn:close()

test_run:cmd('switch test')
-- Both select are empty, because transaction rollback
s1:select()
s2:select()
s1:drop()
s2:drop()
test_run:cmd('switch default')
conn:close()
assert(wait_zero_connection_count())
test_run:cmd("stop server test")

-- Check rollback on disconnect
test_run:cmd("start server test with args='10, true'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]

test_run:cmd("switch test")
s1 = box.schema.space.create('test_1', { engine = 'memtx' })
_ = s1:create_index('primary')
s2 = box.schema.space.create('test_2', { engine = 'vinyl' })
_ = s2:create_index('primary')
test_run:cmd('switch default')

conn = net_box.connect(server_addr)
stream_1 = conn:stream(1)
stream_2 = conn:stream(2)
space_1 = stream_1.space.test_1
space_2 = stream_2.space.test_2
stream_1:begin()
stream_2:begin()

space_1:replace({1})
space_1:replace({2})
-- Select return two previously inserted tuples
space_1:select({})

space_2:replace({1})
space_2:replace({2})
-- Select return two previously inserted tuples
space_2:select({})
conn:close()

test_run:cmd("switch test")
-- Empty selects, transaction was rollback
s1:select()
s2:select()
-- Check that there are no streams and messages, which
-- was not deleted after connection close
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0)
assert(errinj.get('ERRINJ_IPROTO_STREAMS_MSG_COUNT') == 0)
test_run:cmd("switch default")
assert(wait_zero_connection_count())

-- Reconnect
conn = net_box.connect(server_addr)
stream_1 = conn:stream(1)
stream_2 = conn:stream(2)
space_1 = stream_1.space.test_1
space_2 = stream_2.space.test_2
-- We can begin new transactions with same stream_id, because
-- previous one was rollbacked and destroyed.
stream_1:begin()
stream_2:begin()
-- Two empty selects
space_1:select({})
space_2:select({})
stream_1:commit()
stream_2:commit()

test_run:cmd('switch test')
-- Both select are empty, because transaction rollback
s1:select()
s2:select()
s1:drop()
s2:drop()
test_run:cmd('switch default')
conn:close()
assert(wait_zero_connection_count())
test_run:cmd("stop server test")

-- Check rollback on disconnect with big count of async requests
test_run:cmd("start server test with args='10, true'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]

test_run:cmd("switch test")
s1 = box.schema.space.create('test_1', { engine = 'memtx' })
_ = s1:create_index('primary')
s2 = box.schema.space.create('test_2', { engine = 'vinyl' })
_ = s2:create_index('primary')
test_run:cmd('switch default')

conn = net_box.connect(server_addr)
stream_1 = conn:stream(1)
stream_2 = conn:stream(2)
space_1 = stream_1.space.test_1
space_2 = stream_2.space.test_2
stream_1:begin()
stream_2:begin()

space_1:replace({1})
space_1:replace({2})
-- Select return two previously inserted tuples
space_1:select({})

space_2:replace({1})
space_2:replace({2})
-- Select return two previously inserted tuples
space_2:select({})
-- We send a large number of asynchronous requests,
-- their result is not important to us, it is important
-- that they will be in the stream queue at the time of
-- the disconnect.
test_run:cmd("setopt delimiter ';'")
for i = 1, 1000 do
    space_1:replace({i}, {is_async = true})
    space_2:replace({i}, {is_async = true})
end;
test_run:cmd("setopt delimiter ''");
fiber.sleep(0)
conn:close()

test_run:cmd("switch test")
-- Empty selects, transaction was rollback
s1:select()
s2:select()
-- Check that there are no streams and messages, which
-- was not deleted after connection close
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0)
assert(errinj.get('ERRINJ_IPROTO_STREAMS_MSG_COUNT') == 0)
test_run:cmd("switch default")
assert(wait_zero_connection_count())

-- Reconnect
conn = net_box.connect(server_addr)
stream_1 = conn:stream(1)
stream_2 = conn:stream(2)
space_1 = stream_1.space.test_1
space_2 = stream_2.space.test_2
-- We can begin new transactions with same stream_id, because
-- previous one was rollbacked and destroyed.
stream_1:begin()
stream_2:begin()
-- Two empty selects
space_1:select({})
space_2:select({})
stream_1:commit()
stream_2:commit()

test_run:cmd('switch test')
-- Both select are empty, because transaction rollback
s1:select()
s2:select()
s1:drop()
s2:drop()
test_run:cmd('switch default')
conn:close()
assert(wait_zero_connection_count())
test_run:cmd("stop server test")

-- Check that all requests between `begin` and `commit`
-- have correct lsn and tsn values. During my work on the
-- patch, i see that all requests in stream comes with
-- header->is_commit == true, so if we are in transaction
-- in stream we should set this value to false, otherwise
-- during recovering `wal_stream_apply_dml_row` fails, because
-- of LSN/TSN mismatch. Here is a special test case for it.
test_run:cmd("start server test with args='10, true'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]

test_run:cmd("switch test")
s1 = box.schema.space.create('test_1', { engine = 'memtx' })
_ = s1:create_index('primary')
s2 = box.schema.space.create('test_2', { engine = 'memtx' })
_ = s2:create_index('primary')
test_run:cmd('switch default')

conn = net_box.connect(server_addr)
stream_1 = conn:stream()
stream_2 = conn:stream()
space_1 = stream_1.space.test_1
space_2 = stream_2.space.test_2

stream_1:begin()
stream_2:begin()
space_1:replace({1})
space_1:replace({2})
space_2:replace({1})
space_2:replace({2})
stream_1:commit()
stream_2:commit()

test_run:cmd('switch test')
-- Here we get two tuples, commit was successful
s1:select{}
-- Here we get two tuples, commit was successful
s2:select{}
-- Check that there are no streams and messages, which
-- was not deleted after connection close
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0)
assert(errinj.get('ERRINJ_IPROTO_STREAMS_MSG_COUNT') == 0)
test_run:cmd('switch default')
conn:close()
assert(wait_zero_connection_count())
test_run:cmd("stop server test")

test_run:cmd("start server test with args='1, true'")
test_run:cmd('switch test')
-- Here we get two tuples, commit was successful
box.space.test_1:select{}
-- Here we get two tuples, commit was successful
box.space.test_2:select{}
box.space.test_1:drop()
box.space.test_2:drop()
test_run:cmd('switch default')
test_run:cmd("stop server test")

-- Same transactions checks for async mode
test_run:cmd("start server test with args='10, true'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]

test_run:cmd("switch test")
s1 = box.schema.space.create('test_1', { engine = 'memtx' })
_ = s1:create_index('primary')
s2 = box.schema.space.create('test_2', { engine = 'vinyl' })
_ = s2:create_index('primary')
test_run:cmd('switch default')

conn = net_box.connect(server_addr)
assert(conn:ping())
stream_1 = conn:stream()
space_1 = stream_1.space.test_1
stream_2 = conn:stream()
space_2 = stream_2.space.test_2

memtx_futures = {}
memtx_results = {}
memtx_futures["begin"] = stream_1:begin({is_async = true})
memtx_futures["replace"] = space_1:replace({1}, {is_async = true})
memtx_futures["insert"] = space_1:insert({2}, {is_async = true})
memtx_futures["select"] = space_1:select({}, {is_async = true})

vinyl_futures = {}
vinyl_results = {}
vinyl_futures["begin"] = stream_2:begin({is_async = true})
vinyl_futures["replace"] = space_2:replace({1}, {is_async = true})
vinyl_futures["insert"] = space_2:insert({2}, {is_async = true})
vinyl_futures["select"] = space_2:select({}, {is_async = true})

test_run:cmd("switch test")
-- Select is empty, transaction was not commited
s1:select()
s2:select()
test_run:cmd('switch default')
memtx_futures["commit"] = stream_1:commit({is_async = true})
vinyl_futures["commit"] = stream_2:commit({is_async = true})

test_run:cmd("setopt delimiter ';'")
for name, future in pairs(memtx_futures) do
    local err
    memtx_results[name], err = future:wait_result()
    assert(not err)
end;
for name, future in pairs(vinyl_futures) do
    local err
    vinyl_results[name], err = future:wait_result()
    assert(not err)
end;
test_run:cmd("setopt delimiter ''");
-- If begin was successful it return nil
assert(not memtx_results["begin"])
assert(not vinyl_results["begin"])
-- [1]
assert(memtx_results["replace"])
assert(vinyl_results["replace"])
-- [2]
assert(memtx_results["insert"])
assert(vinyl_results["insert"])
-- [1] [2]
assert(memtx_results["select"])
assert(vinyl_results["select"])
-- If commit was successful it return nil
assert(not memtx_results["commit"])
assert(not vinyl_results["commit"])

test_run:cmd("switch test")
-- Select return tuple, which was previously inserted,
-- because transaction was successful
s1:select()
s2:select()
s1:drop()
s2:drop()
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0)
assert(errinj.get('ERRINJ_IPROTO_STREAMS_MSG_COUNT') == 0)
test_run:cmd('switch default')
conn:close()
assert(wait_zero_connection_count())
test_run:cmd("stop server test")

-- Check conflict resolution in stream transactions,
test_run:cmd("start server test with args='10, true'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]

test_run:cmd("switch test")
s1 = box.schema.space.create('test_1', { engine = 'memtx' })
_ = s1:create_index('primary')
s2 = box.schema.space.create('test_2', { engine = 'vinyl' })
_ = s2:create_index('primary')
test_run:cmd('switch default')

conn = net_box.connect(server_addr)
stream_1 = conn:stream()
stream_2 = conn:stream()
space_1_1 = stream_1.space.test_1
space_1_2 = stream_2.space.test_1
space_2_1 = stream_1.space.test_2
space_2_2 = stream_2.space.test_2

futures_1 = {}
results_1 = {}
-- Simple read/write conflict.
futures_1["begin_1"] = stream_1:begin({is_async = true})
futures_1["begin_2"] = stream_2:begin({is_async = true})
futures_1["select_1_1"] = space_1_1:select({1}, {is_async = true})
futures_1["select_1_2"] = space_1_2:select({1}, {is_async = true})
futures_1["replace_1_1"] = space_1_1:replace({1, 1}, {is_async = true})
futures_1["replace_1_2"] = space_1_2:replace({1, 2}, {is_async = true})
futures_1["commit_1"] = stream_1:commit({is_async = true})
futures_1["commit_2"] = stream_2:commit({is_async = true})
futures_1["select_1_1_A"] = space_1_1:select({}, {is_async = true})
futures_1["select_1_2_A"] = space_1_2:select({}, {is_async = true})

test_run:cmd("setopt delimiter ';'")
for name, future in pairs(futures_1) do
    local err
    results_1[name], err = future:wait_result()
    if err then
    	results_1[name] = err
    end
end;
test_run:cmd("setopt delimiter ''");
-- Successful begin return nil
assert(not results_1["begin_1"])
assert(not results_1["begin_2"])
-- []
assert(not results_1["select_1_1"][1])
assert(not results_1["select_1_2"][1])
-- [1]
assert(results_1["replace_1_1"][1])
-- [1]
assert(results_1["replace_1_1"][2])
-- [1]
assert(results_1["replace_1_2"][1])
-- [2]
assert(results_1["replace_1_2"][2])
-- Successful commit return nil
assert(not results_1["commit_1"])
-- Error because of transaction conflict
assert(results_1["commit_2"])
-- [1, 1]
assert(results_1["select_1_1_A"][1])
-- commit_1 could have ended before commit_2, so
-- here we can get both empty select and [1, 1]
-- for results_1["select_1_2_A"][1]

futures_2 = {}
results_2 = {}
-- Simple read/write conflict.
futures_2["begin_1"] = stream_1:begin({is_async = true})
futures_2["begin_2"] = stream_2:begin({is_async = true})
futures_2["select_2_1"] = space_2_1:select({1}, {is_async = true})
futures_2["select_2_2"] = space_2_2:select({1}, {is_async = true})
futures_2["replace_2_1"] = space_2_1:replace({1, 1}, {is_async = true})
futures_2["replace_2_2"] = space_2_2:replace({1, 2}, {is_async = true})
futures_2["commit_1"] = stream_1:commit({is_async = true})
futures_2["commit_2"] = stream_2:commit({is_async = true})
futures_2["select_2_1_A"] = space_2_1:select({}, {is_async = true})
futures_2["select_2_2_A"] = space_2_2:select({}, {is_async = true})

test_run:cmd("setopt delimiter ';'")
for name, future in pairs(futures_2) do
    local err
    results_2[name], err = future:wait_result()
    if err then
    	results_2[name] = err
    end
end;
test_run:cmd("setopt delimiter ''");
-- Successful begin return nil
assert(not results_2["begin_1"])
assert(not results_2["begin_2"])
-- []
assert(not results_2["select_2_1"][1])
assert(not results_2["select_2_2"][1])
-- [1]
assert(results_2["replace_2_1"][1])
-- [1]
assert(results_2["replace_2_1"][2])
-- [1]
assert(results_2["replace_2_2"][1])
-- [2]
assert(results_2["replace_2_2"][2])
-- Successful commit return nil
assert(not results_2["commit_1"])
-- Error because of transaction conflict
assert(results_2["commit_2"])
-- [1, 1]
assert(results_2["select_2_1_A"][1])
-- commit_1 could have ended before commit_2, so
-- here we can get both empty select and [1, 1]
-- for results_1["select_2_2_A"][1]

test_run:cmd('switch test')
-- Both select return tuple [1, 1], transaction commited
s1:select()
s2:select()
s1:drop()
s2:drop()
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0)
assert(errinj.get('ERRINJ_IPROTO_STREAMS_MSG_COUNT') == 0)
test_run:cmd('switch default')
conn:close()
assert(wait_zero_connection_count())
test_run:cmd("stop server test")

-- Checks for iproto call/eval in stream
test_run:cmd("start server test with args='10, true'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]
test_run:cmd("switch test")
s = box.schema.space.create('test', { engine = 'memtx' })
_ = s:create_index('primary')
function ping() return "pong" end
test_run:cmd('switch default')

conn = net_box.connect(server_addr)
assert(conn:ping())
stream = conn:stream()
space = stream.space.test
space_no_stream = conn.space.test

-- successful begin using stream:call
stream:call('box.begin')
-- error: Operation is not permitted when there is an active transaction
stream:eval('box.begin()')
-- error: Operation is not permitted when there is an active transaction
stream:begin()
stream:call('ping')
stream:eval('ping()')
-- error: Operation is not permitted when there is an active transaction
stream:call('box.begin')
stream:eval('box.begin()')
-- successful commit using stream:call
stream:call('box.commit')

-- successful begin using stream:eval
stream:eval('box.begin()')
space:replace({1})
-- Empty select, transaction was not commited and
-- is not visible from requests not belonging to the
-- transaction.
space_no_stream:select{}
-- Select return tuple, which was previously inserted,
-- because this select belongs to transaction.
space:select({})
test_run:cmd("switch test")
-- Select is empty, transaction was not commited
s:select()
test_run:cmd('switch default')
--Successful commit using stream:eval
stream:eval('box.commit()')
-- Select return tuple, which was previously inserted,
-- because transaction was successful
space_no_stream:select{}
test_run:cmd("switch test")
-- Select return tuple, because transaction was successful
s:select()
s:delete{1}
test_run:cmd('switch default')
-- Check rollback using stream:call
stream:begin()
space:replace({2})
-- Empty select, transaction was not commited and
-- is not visible from requests not belonging to the
-- transaction.
space_no_stream:select{}
-- Select return tuple, which was previously inserted,
-- because this select belongs to transaction.
space:select({})
test_run:cmd("switch test")
-- Select is empty, transaction was not commited
s:select()
test_run:cmd('switch default')
--Successful rollback using stream:call
stream:call('box.rollback')
-- Empty selects transaction rollbacked
space:select({})
space_no_stream:select{}
test_run:cmd("switch test")
-- Empty select transaction rollbacked
s:select()
s:drop()
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0)
assert(errinj.get('ERRINJ_IPROTO_STREAMS_MSG_COUNT') == 0)
test_run:cmd('switch default')
conn:close()
assert(wait_zero_connection_count())
test_run:cmd("stop server test")

-- Simple test which demostrates that stream immediately
-- destroyed, when no processing messages in stream and
-- no active transaction.

test_run:cmd("start server test with args='10, true'")
server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]
test_run:cmd("switch test")
s = box.schema.space.create('test', { engine = 'memtx' })
_ = s:create_index('primary')
test_run:cmd('switch default')

conn = net_box.connect(server_addr)
assert(conn:ping())
stream = conn:stream()
space = stream.space.test
for i = 1, 10 do space:replace{i} end
test_run:cmd("switch test")
-- All messages was processed, so stream object was immediately
-- deleted, because no active transaction started.
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0)
assert(errinj.get('ERRINJ_IPROTO_STREAMS_MSG_COUNT') == 0)
s:drop()
test_run:cmd('switch default')
conn:close()
assert(wait_zero_connection_count())
test_run:cmd("stop server test")

-- Transaction tests for sql iproto requests.
-- All this functions are copy-paste from sql/ddl.test.lua,
-- except that they check sql transactions in streams
test_run:cmd("setopt delimiter '$'")
function execute_sql_string(stream, sql_string)
    if stream then
        stream:execute(sql_string)
    else
        box.execute(sql_string)
    end
end$
function execute_sql_string_and_return_result(stream, sql_string)
    if stream then
        return pcall(stream.execute, stream, sql_string)
    else
        return box.execute(sql_string)
    end
end$
function monster_ddl(stream)
    local _, err1, err2, err3, err4, err5, err6
    local stream_or_box = stream or box
    execute_sql_string(stream, [[CREATE TABLE t1(id INTEGER PRIMARY KEY,
                                                 a INTEGER,
                                                 b INTEGER);]])
    execute_sql_string(stream, [[CREATE TABLE t2(id INTEGER PRIMARY KEY,
                                                 a INTEGER,
                                                 b INTEGER UNIQUE,
                                                 CONSTRAINT ck1 CHECK(b < 100));]])

    execute_sql_string(stream, 'CREATE INDEX t1a ON t1(a);')
    execute_sql_string(stream, 'CREATE INDEX t2a ON t2(a);')

    execute_sql_string(stream, 'CREATE TABLE t_to_rename(id INTEGER PRIMARY KEY, a INTEGER);')

    execute_sql_string(stream, 'DROP INDEX t2a ON t2;')

    execute_sql_string(stream, 'CREATE INDEX t_to_rename_a ON t_to_rename(a);')

    execute_sql_string(stream, 'ALTER TABLE t1 ADD CONSTRAINT ck1 CHECK(b > 0);')

    _, err1 = execute_sql_string_and_return_result(stream, 'ALTER TABLE t_to_rename RENAME TO t1;')

    execute_sql_string(stream, 'ALTER TABLE t1 ADD CONSTRAINT ck2 CHECK(a > 0);')
    execute_sql_string(stream, 'ALTER TABLE t1 DROP CONSTRAINT ck1;')

    execute_sql_string(stream, [[ALTER TABLE t1 ADD CONSTRAINT fk1 FOREIGN KEY
                                 (a) REFERENCES t2(b);]])
    execute_sql_string(stream, 'ALTER TABLE t1 DROP CONSTRAINT fk1;')

    _, err2 = execute_sql_string_and_return_result(stream, 'CREATE TABLE t1(id INTEGER PRIMARY KEY);')

    execute_sql_string(stream, [[ALTER TABLE t1 ADD CONSTRAINT fk1 FOREIGN KEY
                                 (a) REFERENCES t2(b);]])

    execute_sql_string(stream, [[CREATE TABLE trigger_catcher(id INTEGER PRIMARY
                                                              KEY AUTOINCREMENT);]])

    execute_sql_string(stream, 'ALTER TABLE t_to_rename RENAME TO t_renamed;')

    execute_sql_string(stream, 'DROP INDEX t_to_rename_a ON t_renamed;')

    execute_sql_string(stream, [[CREATE TRIGGER t1t AFTER INSERT ON t1 FOR EACH ROW
                                 BEGIN
                                     INSERT INTO trigger_catcher VALUES(1);
                                 END; ]])

    _, err3 = execute_sql_string_and_return_result(stream, 'DROP TABLE t3;')

    execute_sql_string(stream, [[CREATE TRIGGER t2t AFTER INSERT ON t2 FOR EACH ROW
                                 BEGIN
                                     INSERT INTO trigger_catcher VALUES(1);
                                 END; ]])

    _, err4 = execute_sql_string_and_return_result(stream, 'CREATE INDEX t1a ON t1(a, b);')

    execute_sql_string(stream, 'TRUNCATE TABLE t1;')
    _, err5 = execute_sql_string_and_return_result(stream, 'TRUNCATE TABLE t2;')
    _, err6 = execute_sql_string_and_return_result(stream, 'TRUNCATE TABLE t_does_not_exist;')

    execute_sql_string(stream, 'DROP TRIGGER t2t;')

    return {'Finished ok, errors in the middle: ', err1, err2, err3, err4,
            err5, err6}
end$
function monster_ddl_cmp_res(res1, res2)
    if json.encode(res1) == json.encode(res2) then
        return true
    end
    return res1, res2
end$
function monster_ddl_is_clean(stream)
    local stream_or_box = stream or box
    assert(stream_or_box.space.T1 == nil)
    assert(stream_or_box.space.T2 == nil)
    assert(stream_or_box.space._trigger:count() == 0)
    assert(stream_or_box.space._fk_constraint:count() == 0)
    assert(stream_or_box.space._ck_constraint:count() == 0)
    assert(stream_or_box.space.T_RENAMED == nil)
    assert(stream_or_box.space.T_TO_RENAME == nil)
end$
function monster_ddl_check(stream)
    local _, err1, err2, err3, err4, res
    local stream_or_box = stream or box
    _, err1 = execute_sql_string_and_return_result(stream, 'INSERT INTO t2 VALUES (1, 1, 101)')
    execute_sql_string(stream, 'INSERT INTO t2 VALUES (1, 1, 1)')
    _, err2 = execute_sql_string_and_return_result(stream, 'INSERT INTO t2 VALUES(2, 2, 1)')
    _, err3 = execute_sql_string_and_return_result(stream, 'INSERT INTO t1 VALUES(1, 20, 1)')
    _, err4 = execute_sql_string_and_return_result(stream, 'INSERT INTO t1 VALUES(1, -1, 1)')
    execute_sql_string(stream, 'INSERT INTO t1 VALUES (1, 1, 1)')
    if not stream then
        assert(stream_or_box.space.T_RENAMED ~= nil)
        assert(stream_or_box.space.T_RENAMED.index.T_TO_RENAME_A == nil)
        assert(stream_or_box.space.T_TO_RENAME == nil)
        res = execute_sql_string_and_return_result(stream, 'SELECT * FROM trigger_catcher')
    else
    	_, res = execute_sql_string_and_return_result(stream, 'SELECT * FROM trigger_catcher')
    end
    return {'Finished ok, errors and trigger catcher content: ', err1, err2,
            err3, err4, res}
end$
function monster_ddl_clear(stream)
    execute_sql_string(stream, 'DROP TRIGGER IF EXISTS t1t;')
    execute_sql_string(stream, 'DROP TABLE IF EXISTS trigger_catcher;')
    execute_sql_string(stream, 'ALTER TABLE t1 DROP CONSTRAINT fk1;')
    execute_sql_string(stream, 'DROP TABLE IF EXISTS t2')
    execute_sql_string(stream, 'DROP TABLE IF EXISTS t1')
    execute_sql_string(stream, 'DROP TABLE IF EXISTS t_renamed')
end$
test_run:cmd("setopt delimiter ''")$

test_run:cmd("start server test with args='10, true'")
test_run:cmd('switch test')
test_run:cmd("setopt delimiter '$'")
function monster_ddl_is_clean()
    if not (box.space.T1 == nil) or
       not (box.space.T2 == nil) or
       not (box.space._trigger:count() == 0) or
       not (box.space._fk_constraint:count() == 0) or
       not (box.space._ck_constraint:count() == 0) or
       not (box.space.T_RENAMED == nil) or
       not (box.space.T_TO_RENAME == nil) then
           return false
    end
    return true
end$
test_run:cmd("setopt delimiter ''")$
test_run:cmd('switch default')

server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]
conn = net_box.connect(server_addr)
stream = conn:stream()

-- No txn.
true_ddl_res = monster_ddl()
true_ddl_res

true_check_res = monster_ddl_check()
true_check_res

monster_ddl_clear()
monster_ddl_is_clean()

-- Both DDL and cleanup in one txn in stream.
ddl_res = nil
stream:execute('START TRANSACTION')
ddl_res = monster_ddl(stream)
monster_ddl_clear(stream)
stream:call('monster_ddl_is_clean')
stream:execute('COMMIT')
monster_ddl_cmp_res(ddl_res, true_ddl_res)

-- DDL in txn, cleanup is not.
stream:execute('START TRANSACTION')
ddl_res = monster_ddl(stream)
stream:execute('COMMIT')
monster_ddl_cmp_res(ddl_res, true_ddl_res)

check_res = monster_ddl_check(stream)
monster_ddl_cmp_res(check_res, true_check_res)

monster_ddl_clear(stream)
stream:call('monster_ddl_is_clean')

-- DDL is not in txn, cleanup is.
ddl_res = monster_ddl(stream)
monster_ddl_cmp_res(ddl_res, true_ddl_res)

check_res = monster_ddl_check(stream)
monster_ddl_cmp_res(check_res, true_check_res)

stream:execute('START TRANSACTION')
monster_ddl_clear(stream)
stream:call('monster_ddl_is_clean')
stream:execute('COMMIT')

-- DDL and cleanup in separate txns.
stream:execute('START TRANSACTION')
ddl_res = monster_ddl(stream)
stream:execute('COMMIT')
monster_ddl_cmp_res(ddl_res, true_ddl_res)

check_res = monster_ddl_check(stream)
monster_ddl_cmp_res(check_res, true_check_res)

stream:execute('START TRANSACTION')
monster_ddl_clear(stream)
stream:call('monster_ddl_is_clean')
stream:execute('COMMIT')

test_run:cmd("switch test")
-- All messages was processed, so stream object was immediately
-- deleted, because no active transaction started.
errinj = box.error.injection
assert(errinj.get('ERRINJ_IPROTO_STREAM_COUNT') == 0)
assert(errinj.get('ERRINJ_IPROTO_STREAMS_MSG_COUNT') == 0)
test_run:cmd('switch default')
conn:close()
assert(wait_zero_connection_count())
test_run:cmd("stop server test")

test_run:cmd("cleanup server test")
test_run:cmd("delete server test")
