test_run = require('test_run').new()


-- Step 1
box.schema.user.grant("guest", "replication")
s = box.schema.space.create("temp", {temporary=true})
_ = s:create_index('pk')
s:insert{1,2}
s:insert{4}
s:select()


-- Step 2
test_run:cmd('create server replica with rpl_master=default,\
              script="replication/replica.lua"')
test_run:cmd('start server replica')


-- Step 3
box.begin() box.space._schema:replace{"smth"} s:truncate() box.commit()
s:select()
box.space._schema:select{'smth'}


-- Step 4
-- Checking that replica has received the last transaction,
-- and that replication isn't broken.
test_run:switch('replica')
box.space._schema:select{'smth'}
box.info.replication[1].upstream.status


test_run:switch('default')
test_run:cmd('stop server replica')
test_run:cmd('cleanup server replica')
test_run:cmd('delete server replica')
