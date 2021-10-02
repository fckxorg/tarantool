-- tags: vinyl

test_run = require('test_run').new()
test_run:cmd("push filter 'Invalid VYLOG file: Slice [0-9]+ deleted but not registered'" .. \
             "to 'Invalid VYLOG file: Slice <NUM> deleted but not registered'")

s = box.schema.create_space('test', {engine = 'vinyl'})
pk = s:create_index('pk')
s:insert{1, 1}
box.snapshot()

-- Let's test number of upserts in one transaction that exceeds
-- the limit of operations allowed in one update.
--
ups_cnt = 5000
box.begin()
for i = 1, ups_cnt do s:upsert({1}, {{'|', 2, i}}) end
box.commit()
-- Since 2.6 update operations of single upsert are applied consistently.
-- So despite upserts' update operations can be squashed, they are anyway
-- applied as they come in corresponding upserts. The same concerns the
-- second test.
--
box.snapshot()
s:select()

s:drop()

s = box.schema.create_space('test', {engine = 'vinyl'})
pk = s:create_index('pk')

tuple = {}
for i = 1, ups_cnt do tuple[i] = i end
_ = s:insert(tuple)
box.snapshot()

box.begin()
for k = 2, ups_cnt do s:upsert({1}, {{'+', k, 1}}) end
box.commit()
box.snapshot()
s:select()[1][ups_cnt]

s:drop()

-- Test that single upsert with too many (> 4000) operations doesn't
-- pass check so it is rejected.
--
s = box.schema.create_space('test', {engine = 'vinyl'})
pk = s:create_index('pk')

ups_ops = {}
for k = 2, ups_cnt do ups_ops[k] = {'+', k, 1} end
s:upsert({1}, ups_ops)
s:select()
s:drop()

-- restart the current server to resolve the issue #5141
-- which reproduced in test:
--   vinyl/gh-5141-invalid-vylog-file.test.lua
test_run:cmd("restart server default with cleanup=True")


