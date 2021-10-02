#!/usr/bin/env tarantool

-- tags: app

os.setenv('TEST_VAR', '48')
box.cfg { log = '|echo $TEST_VAR; cat > /dev/null' }
os.exit(0)
