## feature/core

 * Add new  metrics `STREAM_QUEUE_MAX`, to `box.stat.net`. This metric
   contain two counters `current` (displays the current length of the
   longest stream queue) and `total` (displays the maximal length of
   the stream queue for all time). (gh-6293).
