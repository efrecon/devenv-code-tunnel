#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for share/orchestration/logrotate.sh: run logrotate on all the .log
# files of a directory.

setup() {
  require_cmd logrotate
  LOGDIR=$TEST_TMPDIR/logs
  STATUS=$TEST_TMPDIR/state/logrotate.status
  mkdir -p "$LOGDIR/sub"
  printf 'some log\n' > "$LOGDIR/one.log"
  printf 'other log\n' > "$LOGDIR/sub/two.log"
  printf 'not a log\n' > "$LOGDIR/notes.txt"
}

test_rotates_log_files() {
  run_orchestration logrotate -L "$LOGDIR" -s "$STATUS"
  assert_file "$STATUS"
  status=$(cat "$STATUS")
  assert_contains "$status" "$LOGDIR/one.log"
  assert_contains "$status" "$LOGDIR/sub/two.log"
  assert_not_contains "$status" "notes.txt"
  assert_eq 0 "$(find "$TEST_TMPDIR" -maxdepth 1 -name 'logrotate.*.conf' | wc -l | tr -d ' ')" "configuration removed"
}
