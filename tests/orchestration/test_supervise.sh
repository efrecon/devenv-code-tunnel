#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for share/orchestration/supervise.sh: run a program and restart it,
# with an increasing delay, until it succeeds.

setup() {
  COUNT=$TEST_TMPDIR/count
  # Fail as many times as the content of the counter file, then succeed.
  # Record the arguments of each run.
  make_script "$TEST_TMPDIR/flaky.sh" <<EOF
#!/bin/sh
echo "\$*" >> "$TEST_TMPDIR/runs"
n=\$(cat "$COUNT")
if [ "\$n" -gt 0 ]; then
  echo \$((n - 1)) > "$COUNT"
  exit 1
fi
exit 0
EOF
}

_runs() { wc -l < "$TEST_TMPDIR/runs" | tr -d ' '; }

test_runs_once_on_success() {
  echo 0 > "$COUNT"
  run_orchestration supervise -n flaky -b "$TEST_TMPDIR/flaky.sh" -- one two
  assert_eq 1 "$(_runs)"
  assert_eq "one two" "$(cat "$TEST_TMPDIR/runs")" "arguments passed"
}

test_restarts_until_success() {
  echo 2 > "$COUNT"
  run_orchestration supervise -b "$TEST_TMPDIR/flaky.sh"
  assert_eq 3 "$(_runs)"
  assert_eq 0 "$(cat "$COUNT")"
}

test_binary_from_environment() {
  echo 0 > "$COUNT"
  SUPERVISE_BINPATH=$TEST_TMPDIR/flaky.sh run_orchestration supervise
  assert_eq 1 "$(_runs)"
}

test_requires_binary() {
  assert_fails run_orchestration supervise
}
