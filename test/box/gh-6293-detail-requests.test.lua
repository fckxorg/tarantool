env = require('test_run')
net_box = require('net.box')
test_run = env.new()
test_run:cmd("create server test with script=\
              'box/gh-5645-several-iproto-threads.lua'")

test_run:cmd("setopt delimiter ';'")
function get_network_requests_stats_using_call(rtype)
    local box_stat_net = test_run:cmd(string.format(
        "eval test 'return box.stat.net()'"
    ))[1]
    local total = box_stat_net.REQUESTS[rtype]
    local in_progress = box_stat_net.REQUESTS_IN_PROGRESS[rtype]
    local in_stream_queue = box_stat_net.REQUESTS_IN_STREAM_QUEUE[rtype]
    local in_cbus_queue = box_stat_net.REQUESTS_IN_CBUS_QUEUE[rtype]
    return total, in_progress, in_stream_queue, in_cbus_queue
end;
function get_network_requests_stats_for_thread_using_call(thread_id, rtype)
    local box_stat_net = test_run:cmd(string.format(
        "eval test 'return box.stat.net.thread()'"
    ))[1][thread_id]
    local total = box_stat_net.REQUESTS[rtype]
    local in_progress = box_stat_net.REQUESTS_IN_PROGRESS[rtype]
    local in_stream_queue = box_stat_net.REQUESTS_IN_STREAM_QUEUE[rtype]
    local in_cbus_queue = box_stat_net.REQUESTS_IN_CBUS_QUEUE[rtype]
    return total, in_progress, in_stream_queue, in_cbus_queue
end;
function get_network_requests_stats_using_index(rtype)
    local total = test_run:cmd(string.format(
        "eval test 'return box.stat.net.%s.%s'",
        "REQUESTS", rtype
    ))[1]
    local in_progress = test_run:cmd(string.format(
        "eval test 'return box.stat.net.%s.%s'",
        "REQUESTS_IN_PROGRESS", rtype
    ))[1]
    local in_stream_queue = test_run:cmd(string.format(
        "eval test 'return box.stat.net.%s.%s'",
        "REQUESTS_IN_STREAM_QUEUE", rtype
    ))[1]
    local in_cbus_queue = test_run:cmd(string.format(
        "eval test 'return box.stat.net.%s.%s'",
        "REQUESTS_IN_CBUS_QUEUE", rtype
    ))[1]
    return total, in_progress, in_stream_queue, in_cbus_queue
end;
function get_network_requests_stats_for_thread_using_index(thread_id, rtype)
    local total = test_run:cmd(string.format(
        "eval test 'return box.stat.net.thread[%d].%s.%s'",
        thread_id, "REQUESTS", rtype
    ))[1]
    local in_progress = test_run:cmd(string.format(
        "eval test 'return box.stat.net.thread[%d].%s.%s'",
        thread_id, "REQUESTS_IN_PROGRESS", rtype
    ))[1]
    local in_stream_queue = test_run:cmd(string.format(
        "eval test 'return box.stat.net.thread[%d].%s.%s'",
        thread_id, "REQUESTS_IN_STREAM_QUEUE", rtype
    ))[1]
    local in_cbus_queue = test_run:cmd(string.format(
        "eval test 'return box.stat.net.thread[%d].%s.%s'",
        thread_id, "REQUESTS_IN_CBUS_QUEUE", rtype
    ))[1]
    return total, in_progress, in_stream_queue, in_cbus_queue
end;
test_run:cmd("setopt delimiter ''");

-- We check that statistics gathered per each thread in sum is equal to
-- statistics gathered from all threads.
thread_count = 5
test_run:cmd(string.format("start server test with args=\"%s\"", thread_count))
test_run:switch("test")
fiber = require('fiber')
function ping() fiber.sleep(0.1) return "pong" end
test_run:switch("default")

server_addr = test_run:cmd("eval test 'return box.cfg.listen'")[1]
conn = net_box.new(server_addr)
stream = conn:new_stream()
request_count = 20
service_total_msg_count, service_in_progress_msg_count, \
service_stream_msg_count, service_cbus_queue_msg_count = \
    get_network_requests_stats_using_call("total");
math.randomseed(os.clock())

test_run:cmd("setopt delimiter ';'")
for i = 1, request_count do
    conn:call("ping", {}, {is_async = true})
    stream:call("ping", {}, {is_async = true})
end;
total, in_progress, in_stream_queue, in_cbus_queue =
    get_network_requests_stats_using_call("current");
assert(total == in_progress + in_stream_queue + in_cbus_queue);
assert(total ~= 0)
for thread_id = 1, thread_count do
    local total, in_progress, in_stream_queue, in_cbus_queue =
        get_network_requests_stats_for_thread_using_call(
            thread_id, "current"
        )
    assert(total == in_progress + in_stream_queue + in_cbus_queue)
end;
test_run:cmd("setopt delimiter ''");
test_run:switch("test")
test_run:wait_cond(function () \
    return box.stat.net().REQUESTS.current == 0 \
end)
test_run:switch("default")
test_run:cmd("setopt delimiter ';'")
total, in_progress, in_stream_queue, in_cbus_queue = 0, 0, 0, 0;
for thread_id = 1, thread_count do
    local total_thd_t_call, in_progress_thd_t_call, in_stream_queue_thd_t_call,
          in_cbus_queue_thd_t_call =
          get_network_requests_stats_for_thread_using_call(thread_id, "total")
    local total_thd_t_index, in_progress_thd_t_index,
          in_stream_queue_thd_t_index, in_cbus_queue_thd_t_index =
          get_network_requests_stats_for_thread_using_index(thread_id, "total")
    assert(
        total_thd_t_call == total_thd_t_index and
    	in_progress_thd_t_call == in_progress_thd_t_index and
    	in_stream_queue_thd_t_call == in_stream_queue_thd_t_index and
    	in_cbus_queue_thd_t_call == in_cbus_queue_thd_t_index
    )
    total = total + total_thd_t_call
    in_progress = in_progress + in_progress_thd_t_call
    in_stream_queue = in_stream_queue + in_stream_queue_thd_t_call
    in_cbus_queue = in_cbus_queue + in_cbus_queue_thd_t_call
end;
total_t_call, in_progress_t_call, in_stream_queue_t_call,
in_cbus_queue_t_call =
    get_network_requests_stats_using_call("total");
total_t_index, in_progress_t_index, in_stream_queue_t_index,
in_cbus_queue_t_index =
    get_network_requests_stats_using_index("total");
assert(
    total_t_call == total_t_index and
    in_progress_t_call == in_progress_t_index and
    in_stream_queue_t_call == in_stream_queue_t_index and
    in_cbus_queue_t_call == in_cbus_queue_t_index
);
assert(
    total == total_t_call and
    in_progress == in_progress_t_call and
    in_stream_queue == in_stream_queue_t_call and
    in_cbus_queue == in_cbus_queue_t_call
)
-- We do not take into account service messages which was sent
-- when establishing a connection
assert(
    total_t_call == 2 * request_count + service_total_msg_count and
    in_progress_t_call  == 2 * request_count + service_in_progress_msg_count and
    in_cbus_queue_t_call == 2 * request_count + service_cbus_queue_msg_count
);
test_run:cmd("setopt delimiter ''");
conn:close()

test_run:cmd("stop server test")
test_run:cmd("cleanup server test")
test_run:cmd("delete server test")
