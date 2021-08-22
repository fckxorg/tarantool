## bugfix/sql

* The HEX() SQL built-in function now does not throw an assert on receiving
  varbinary values that consist of zero-bytes (gh-6113).

