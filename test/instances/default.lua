#!/usr/bin/env tarantool
local helpers = require('test.luatest_helpers.helpers')

box.cfg(helpers.box_cfg())
box.schema.user.grant('guest', 'super', nil, nil, {if_not_exists = true})

_G.ready = true
