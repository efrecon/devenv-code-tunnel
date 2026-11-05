#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for lib/wait.sh

setup() {
  load_lib log common system wait
  LOG=$TEST_TMPDIR/watched.log
}

# Number of tail processes following the watched log.
_tails() { procs_matching "^tail .*${LOG}"; }

# Handler for when_infile: record the line, accept it only when it contains
# "accept".
_record() {
  printf '%s\n' "$1" >> "$TEST_TMPDIR/handled"
  printf %s\\n "$1" | grep -q accept
}

test_wait_file_waits_for_creation() {
  ( sleep 0.5; touch "$LOG" ) &
  wait_file "$LOG"
  assert_file "$LOG"
}

test_wait_infile_returns_first_match() {
  printf 'one\nfound: a\nfound: b\n' > "$LOG"
  assert_eq "found: a" "$(wait_infile "$LOG" 'found')"
}

test_match_in_pairs() {
  assert_eq fn_b "$(_match_in_pairs "error: x" E '^ok' fn_a 'error' fn_b)"
  assert_eq fn_a "$(_match_in_pairs "ok" F 'ok' fn_a 'ok' fn_b)" "first match wins"
  assert_false _match_in_pairs "nothing" E 'ok' fn_a
}

test_file_size() {
  assert_eq 0 "$(file_size "$TEST_TMPDIR/missing")"
  printf '12345\n' > "$LOG"
  assert_eq 6 "$(file_size "$LOG")"
  assert_fails file_size ""
}

test_when_infile_requires_arguments() {
  assert_fails when_infile "" "$LOG" E 'x' -
  assert_fails when_infile 0 "" E 'x' -
  assert_fails when_infile 0 "$LOG" "" 'x' -
}

test_when_infile_returns_matching_line() {
  ( sleep 0.5; printf 'noise\nURL https://example.com\n' >> "$LOG" ) &
  assert_eq "URL https://example.com" "$(when_infile 0 "$LOG" E '^URL ' -)"
}

test_when_infile_waits_for_file() {
  ( sleep 0.5; printf 'URL created later\n' > "$LOG" ) &
  assert_eq "URL created later" "$(when_infile 0 "$LOG" E '^URL ' -)"
}

test_when_infile_ignores_content_before_offset() {
  printf 'URL stale\n' > "$LOG"
  offset=$(file_size "$LOG")
  ( sleep 0.5; printf 'URL fresh\n' >> "$LOG" ) &
  assert_eq "URL fresh" "$(when_infile "$offset" "$LOG" E '^URL ' -)"
}

test_when_infile_sees_lines_written_before_it_starts() {
  printf 'old\n' > "$LOG"
  offset=$(file_size "$LOG")
  # Written after the offset was taken, but before watching starts.
  printf 'URL raced\n' >> "$LOG"
  assert_eq "URL raced" "$(when_infile "$offset" "$LOG" E '^URL ' -)"
}

test_when_infile_handler_decides() {
  printf 'match reject\nmatch accept\nmatch later\n' > "$LOG"
  assert_eq "match accept" "$(when_infile 0 "$LOG" E '^match' _record)"
  assert_eq "match reject
match accept" "$(cat "$TEST_TMPDIR/handled")" "handler called until it accepts"
}

test_when_infile_dispatches_to_pairs() {
  printf 'error: something\nready accept\n' > "$LOG"
  out=$(when_infile 0 "$LOG" E '^error' - '^ready' _record)
  assert_eq "error: something" "$out" "first matching line, first function"
  assert_no_file "$TEST_TMPDIR/handled"
}

test_when_infile_kills_tail_on_return() {
  [ -d /proc/self ] || skip "no /proc"
  printf 'URL here\n' > "$LOG"
  when_infile 0 "$LOG" E '^URL ' - >/dev/null
  wait_until 5 '[ "$(_tails)" -eq 0 ]'
  assert_eq 0 "$(find "$TEST_TMPDIR" -name 'when_infile.*' | wc -l | tr -d ' ')" "pid file removed"
}

test_when_infile_stop_from_outside() {
  [ -d /proc/self ] || skip "no /proc"
  : > "$LOG"
  pidfile=$(mktemp_ext watcher pid)
  (
    _WHEN_INFILE_PIDFILE=$pidfile
    when_infile 0 "$LOG" E 'never matches' - >/dev/null
    echo "returned" > "$TEST_TMPDIR/watcher.done"
  ) &
  watcher=$!
  wait_until 5 '[ "$(_tails)" -eq 1 ]'
  when_infile_stop "$pidfile"
  wait "$watcher"
  assert_file "$TEST_TMPDIR/watcher.done"
  wait_until 5 '[ "$(_tails)" -eq 0 ]'
}

test_when_infile_stop_without_tail_is_harmless() {
  pidfile=$(mktemp_ext empty pid)
  when_infile_stop "$pidfile"
}

test_wait_process_end() {
  # Not a child of this shell, otherwise it would linger as a zombie until
  # waited for, and kill -0 would still succeed.
  pid=$(sh -c 'sleep 0.5 >/dev/null 2>&1 & echo $!')
  wait_process_end "$pid"
  assert_false kill -0 "$pid"
}
