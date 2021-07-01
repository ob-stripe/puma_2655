# puma_2655
Sample project for https://github.com/puma/puma/issues/2655

## Steps to reproduce

1. Clone the repo
2. Start Puma server in one terminal with `bundle exec puma -C puma.rb`
3. Start tailing the custom log file in another terminal with `tail -f /tmp/puma_2655.log`
4. Start the client script with `bundle exec control_client.rb`
5. Wait until the client script starts emitting "Error: Excon::Error::Timeout (read timeout reached)" repeatedly. This means the bug has been triggered.

The last lines in the the `/tmp/puma_2655.log` will look similar to this:
```
!!! adding work << pid=38519 @spawned=1 @waiting=1 @todo.size=1
!!! busy_threads pid=38519 @spawned=1 @waiting=1 @todo.size=0 busy_threads=0
!!! requesting thread trim pid=38519 @spawned=1 @waiting=1 @trim_requested=1
!!! adding work << pid=38519 @spawned=1 @waiting=1 @todo.size=1
!!! busy_threads pid=38519 @spawned=1 @waiting=1 @todo.size=1 busy_threads=1
!!! trimming thread pid=38519 thread="puma threadpool 001" @spawned=0 @waiting=0 @trim_requested=0
```
