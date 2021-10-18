test_run = require('test_run').new()
net_box = require('net.box')
fio = require('fio')

default_listen_addr = box.cfg.listen
test_run:cmd("setopt delimiter ';'")
function create_uri_table(addr, count)
    local uris_table = {}
    local ascii_A = 97
    for i = 1, count do
        local ascii_code = ascii_A + i - 1
        uris_table[i] = addr .. string.upper(string.char(ascii_code))
    end
    return uris_table
end;
function check_connection(port)
    local conn = net_box.connect(port)
    assert(conn:ping())
    conn:close()
end;
test_run:cmd("setopt delimiter ''");

-- Check connection if listening uri passed as a single port number.
port_number = 3301
box.cfg{listen = port_number}
assert(box.cfg.listen == tostring(port_number))
check_connection(port_number)

-- Check connection if listening uri passed as a single string.
box.cfg{listen = default_listen_addr}
assert(box.cfg.listen == default_listen_addr)
check_connection(default_listen_addr)

-- Check connection if listening uri passed as a table of port numbers.
port_numbers = {3301, 3302, 3303, 3304, 3305}
box.cfg{listen = port_numbers}
for i, port_number in ipairs(port_numbers) do \
    assert(box.cfg.listen[i] == tostring(port_number)) \
    check_connection(port_number) \
end

-- Check connection if listening uri passed as a table of strings.
uri_table = create_uri_table(default_listen_addr, 5)
box.cfg{listen = uri_table}
for i, uri in ipairs(uri_table) do \
    assert(box.cfg.listen[i] == uri) \
    assert(fio.path.exists(uri)) \
    check_connection(uri) \
end

box.cfg{listen = default_listen_addr}
for i, uri in ipairs(uri_table) do \
    assert(not fio.path.exists(uri)) \
end
assert(fio.path.exists(default_listen_addr))

-- Special test case to check that all unix socket paths deleted
-- in case when `listen` fails because of invalid uri. Iproto performs
-- `bind` and `listen` operations sequentially to all uris from the list,
-- so we need to make sure that all resources for those uris for which
-- everything has already completed will be successfully cleared in case
-- of error for one of the next uri in list.
uri_table = create_uri_table(default_listen_addr, 5)
uri_table[#uri_table + 1] = "baduri:1"
uri_table[#uri_table + 1] = default_listen_addr .. "X"

-- can't resolve uri for bind
box.cfg{listen = uri_table}
for i, uri in ipairs(uri_table) do \
    assert(not fio.path.exists(uri)) \
end
