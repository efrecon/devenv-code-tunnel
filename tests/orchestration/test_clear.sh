#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the scripts and in wait_until
# Tests for share/orchestration/clear.sh: run a command without the variables
# matching some prefixes.

setup() {
  OUT=$TEST_TMPDIR/out
  TUNNEL_ONE=1
  TUNNEL_with_lower2=2
  OTHER_ONE=kept
  MYPFX_A=a
  export TUNNEL_ONE TUNNEL_with_lower2 OTHER_ONE MYPFX_A
  # Set by the test framework, not needed here.
  unset TUNNEL_PREFIX
}

# Print the variables of interest, as seen by the command.
_env() { env | grep -E '^(TUNNEL|OTHER|MYPFX)_' | sort; }

test_removes_tunnel_variables_by_default() {
  run_orchestration clear -- sh -c 'env | grep -E "^(TUNNEL|OTHER|MYPFX)_" | sort' > "$OUT"
  assert_eq "MYPFX_A=a
OTHER_ONE=kept" "$(cat "$OUT")"
  assert_contains "$(_env)" "TUNNEL_ONE=1" "caller untouched"
}

test_several_prefixes() {
  run_orchestration clear -p TUNNEL -p MYPFX -- sh -c 'env | grep -E "^(TUNNEL|OTHER|MYPFX)_" | sort' > "$OUT"
  assert_eq "OTHER_ONE=kept" "$(cat "$OUT")"
}

test_prefixes_from_environment() {
  CLEAR_PREFIXES="MYPFX OTHER" run_orchestration clear -- sh -c 'env | grep -E "^(TUNNEL|OTHER|MYPFX)_" | sort' > "$OUT"
  assert_eq "TUNNEL_ONE=1
TUNNEL_with_lower2=2" "$(cat "$OUT")"
}

test_keeps_arguments_and_exit_code() {
  rc=0
  run_orchestration clear -- sh -c 'echo "$# $1 $2"; exit 5' sh "a b" c > "$OUT" || rc=$?
  assert_eq 5 "$rc"
  assert_eq "2 a b c" "$(cat "$OUT")"
}

test_replaces_itself_with_the_command() {
  # The command keeps the PID of clear.sh, so it can be waited for and signalled.
  # shellcheck disable=SC2086 # TESTS_SHELL can contain arguments
  ${TESTS_SHELL:-sh} "$(orchestration clear)" -- sh -c 'echo $$ > "$1"; sleep 30' sh "$TEST_TMPDIR/pid" &
  pid=$!
  wait_until 5 '[ -s "$TEST_TMPDIR/pid" ]'
  assert_eq "$pid" "$(cat "$TEST_TMPDIR/pid")"
  kill "$pid"
  wait "$pid" 2>/dev/null || true
}

test_logs_with_tunnel_settings() {
  # Read before being cleared.
  TUNNEL_VERBOSE=2 TUNNEL_LOG=1 run_orchestration clear -- true > "$OUT"
  assert_contains "$(cat "$OUT")" "Removing TUNNEL_* variables"
}

test_rejects_invalid_prefix() {
  assert_fails run_orchestration clear -p 'A-B' -- true
  assert_fails run_orchestration clear -p '1A' -- true
}

test_requires_command() {
  assert_fails run_orchestration clear
}
