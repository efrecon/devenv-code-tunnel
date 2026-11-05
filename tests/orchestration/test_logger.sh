#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for share/orchestration/logger.sh: reprint log lines, from stdin or a
# followed file, under the name of their source.

setup() {
  load_lib log common system
  LOGGER_LOG=1
  export LOGGER_LOG
}

test_relog_stdin_with_source_tag() {
  out=$(printf 'plain line\n' | run_orchestration logger -s 10-mysource.sh)
  assert_match "$out" '^>+mysource<+ \[LOG\] \[[0-9]{8}-[0-9]{6}\] plain line$'
}

test_relog_removes_existing_header_and_colours() {
  esc=$(printf '\033')
  printf '>>>>>lwrap<<<< [NFO] [20260101-120000] hello\n' > "$TEST_TMPDIR/in"
  printf '%s[1;90m>%s[0m>>lwrap<< [WRN] [20260101-120000] coloured\n' "$esc" "$esc" >> "$TEST_TMPDIR/in"
  out=$(run_orchestration logger -s src < "$TEST_TMPDIR/in")
  assert_contains "$out" "] hello"
  assert_contains "$out" "] coloured"
  assert_not_contains "$out" "[NFO]"
  assert_not_contains "$out" "20260101-120000"
  assert_not_contains "$out" "$esc"
}

test_follow_file() {
  log=$TEST_TMPDIR/followed.log
  run_orchestration logger -s follower -- "$log" > "$TEST_TMPDIR/out" &
  pid=$!
  sleep 0.3
  printf 'first\n' > "$log"
  wait_until 5 'grep -q first "$TEST_TMPDIR/out"'
  printf 'second\n' >> "$log"
  wait_until 5 'grep -q second "$TEST_TMPDIR/out"'
  kill_tree "$pid" >/dev/null 2>&1 || true
  wait "$pid" 2>/dev/null || true
}
