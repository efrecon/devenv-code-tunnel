#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for share/orchestration/notify.sh: run a command when a file changes.
# Uses inotifywait when available, polling otherwise.

setup() {
  load_lib log common system
  FILE=$TEST_TMPDIR/watched.txt
  OUT=$TEST_TMPDIR/changes
  make_script "$TEST_TMPDIR/record.sh" <<EOF
#!/bin/sh
echo "\$NOTIFY_CHANGE \$*" >> "$OUT"
EOF
}

_mode() {
  if command -v inotifywait >/dev/null 2>&1; then echo inotify; else echo poll; fi
}

_lines() { if [ -f "$OUT" ]; then wc -l < "$OUT" | tr -d ' '; else echo 0; fi; }

_stop() {
  kill_tree "$1" >/dev/null 2>&1 || true
  wait "$1" 2>/dev/null || true
}

test_runs_command_on_creation_and_change() {
  run_orchestration notify -f "$FILE" -s 1 -r 0 -- "$TEST_TMPDIR/record.sh" arg &
  pid=$!
  sleep 1 # Let notify settle, inotifywait needs to be watching.
  printf 'created\n' > "$FILE"
  wait_until 10 '[ "$(_lines)" -ge 1 ]'
  assert_eq "$FILE arg" "$(head -n 1 "$OUT")" "changed file exported in NOTIFY_CHANGE ($(_mode))"
  # Polling compares modification times with a resolution of one second.
  sleep 1.1
  printf 'changed\n' >> "$FILE"
  wait_until 10 '[ "$(_lines)" -ge 2 ]'
  _stop "$pid"
}

test_respite_delays_command() {
  run_orchestration notify -f "$FILE" -s 1 -r 2 -- "$TEST_TMPDIR/record.sh" &
  pid=$!
  sleep 1
  printf 'created\n' > "$FILE"
  sleep 0.5
  assert_eq 0 "$(_lines)" "command should wait for the respite"
  wait_until 10 '[ "$(_lines)" -ge 1 ]'
  _stop "$pid"
}

test_requires_path() {
  assert_fails run_orchestration notify -- true
}

test_rejects_non_integer_settings() {
  assert_fails run_orchestration notify -f "$FILE" -s abc -- true
}
