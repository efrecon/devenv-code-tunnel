#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for share/orchestration/timestamp.sh: add or update a "Last updated:"
# line in a file, once or at regular intervals.

TS_RE='[0-9]{8}-[0-9]{6}[+-][0-9]{4}'

setup() {
  FILE=$TEST_TMPDIR/details.txt
}

test_adds_timestamp_once() {
  printf 'some details\n' > "$FILE"
  run_orchestration timestamp -s 0 -- "$FILE"
  assert_eq "some details" "$(head -n 1 "$FILE")" "content kept"
  assert_match "$(tail -n 1 "$FILE")" "^Last updated: ${TS_RE}$"
}

test_updates_in_place() {
  printf 'some details\nLast updated: 20000101-000000+0000\nmore\n' > "$FILE"
  run_orchestration timestamp -s 0 -- "$FILE"
  run_orchestration timestamp -s 0 -- "$FILE"
  assert_eq 1 "$(grep -c '^Last updated: ' "$FILE")"
  assert_not_contains "$(cat "$FILE")" "20000101-000000"
  assert_eq "more" "$(tail -n 1 "$FILE")" "line kept in place"
}

test_custom_header_with_special_characters() {
  : > "$FILE"
  run_orchestration timestamp -s 0 -H 'Seen [at] a|b & c.: ' -- "$FILE"
  run_orchestration timestamp -s 0 -H 'Seen [at] a|b & c.: ' -- "$FILE"
  assert_eq 1 "$(wc -l < "$FILE" | tr -d ' ')"
  assert_match "$(cat "$FILE")" "^Seen \[at\] a\|b & c\.: ${TS_RE}$"
}

test_pipe_in_header_is_literal() {
  # With \| as alternation, "^A\|B: " would match the first line, and the
  # timestamp would never be added.
  printf 'A note\nother B: line\n' > "$FILE"
  run_orchestration timestamp -s 0 -H 'A|B: ' -- "$FILE"
  assert_match "$(tail -n 1 "$FILE")" "^A\|B: ${TS_RE}$" "timestamp added"
  assert_eq "A note" "$(head -n 1 "$FILE")" "other lines untouched"
  run_orchestration timestamp -s 0 -H 'A|B: ' -- "$FILE"
  assert_eq 3 "$(wc -l < "$FILE" | tr -d ' ')" "updated in place"
}

test_path_from_environment() {
  : > "$FILE"
  TIMESTAMP_PATH=$FILE run_orchestration timestamp -s 0
  assert_match "$(cat "$FILE")" "^Last updated: "
}

test_requires_path() {
  assert_fails run_orchestration timestamp -s 0
}

test_periodic_updates() {
  load_lib log common system
  : > "$FILE"
  run_orchestration timestamp -s 1 -- "$FILE" &
  pid=$!
  wait_until 5 'grep -q "^Last updated: " "$FILE"'
  first=$(cat "$FILE")
  wait_until 5 '[ "$(cat "$FILE")" != "$first" ]'
  kill_tree "$pid" >/dev/null 2>&1 || true
  wait "$pid" 2>/dev/null || true
  assert_eq 1 "$(wc -l < "$FILE" | tr -d ' ')"
}
