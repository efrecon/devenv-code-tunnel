#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for share/orchestration/lwrap.sh: run a command, sending its output to a
# log file named after it, under $TUNNEL_PREFIX/log.

setup() {
  make_script "$TEST_TMPDIR/mytool.sh" <<'EOF'
#!/bin/sh
echo "out $*"
echo "err $*" >&2
exit 4
EOF
}

test_print_log_location() {
  assert_eq "$TUNNEL_PREFIX/log/mytool.log" "$(run_orchestration lwrap -L -- "$TEST_TMPDIR/mytool.sh")"
  assert_true test -d "$TUNNEL_PREFIX/log"
}

test_log_location_uses_clean_name() {
  assert_eq "$TUNNEL_PREFIX/log/sshd.log" "$(run_orchestration lwrap -L -- /usr/sbin/20-sshd.sh)"
}

test_output_goes_to_log() {
  rc=0
  out=$(run_orchestration lwrap -- "$TEST_TMPDIR/mytool.sh" a b) || rc=$?
  assert_eq 4 "$rc" "exit code of the wrapped command"
  assert_eq "" "$out" "nothing printed"
  log=$(cat "$TUNNEL_PREFIX/log/mytool.log")
  assert_contains "$log" "$TEST_TMPDIR/mytool.sh a b" "command line logged first"
  assert_contains "$log" "out a b"
  assert_contains "$log" "err a b"
}

test_log_is_appended() {
  run_orchestration lwrap -- "$TEST_TMPDIR/mytool.sh" first || true
  run_orchestration lwrap -- "$TEST_TMPDIR/mytool.sh" second || true
  log=$(cat "$TUNNEL_PREFIX/log/mytool.log")
  assert_contains "$log" "out first"
  assert_contains "$log" "out second"
}

test_requires_command() {
  assert_fails run_orchestration lwrap
}

test_log_name_option() {
  assert_eq "$TUNNEL_PREFIX/log/realname.log" \
    "$(run_orchestration lwrap -L -n realname -- "$TEST_TMPDIR/mytool.sh")"
  run_orchestration lwrap -n realname -- "$TEST_TMPDIR/mytool.sh" named || true
  assert_contains "$(cat "$TUNNEL_PREFIX/log/realname.log")" "out named"
  assert_no_file "$TUNNEL_PREFIX/log/mytool.log"
}

test_log_name_from_environment() {
  assert_eq "$TUNNEL_PREFIX/log/fromenv.log" \
    "$(LWRAP_NAME=fromenv run_orchestration lwrap -L -- "$TEST_TMPDIR/mytool.sh")"
}
