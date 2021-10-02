#!/usr/bin/env tarantool

-- tags: vinyl

test_run = require('test_run').new()
large = require('large')

large.prepare()
large.large(500)

test_run:cmd('restart server default')

large = require('large')
large.check()
large.teardown()
