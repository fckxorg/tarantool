test_run = require('test_run').new()
net_box = require('net.box')

old_listen = box.cfg.listen
box.cfg{listen = 3301}
conn = net_box.connect(3301)
assert(conn:ping())
conn:close()
