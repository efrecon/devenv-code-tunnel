#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the scripts and in wait_until
# Tests for share/tunnels/code.sh, against a fake code CLI. The fake records its
# arguments in $FAKE_CALLS, prints a device code when logging in, and prints a
# tunnel URL when started, or errors $FAKE_FAILURES times first.

setup() {
  load_lib log common system
  fake_path
  FAKE_CALLS=$TEST_TMPDIR/calls
  GIST=$TEST_TMPDIR/gist.txt
  OUT=$TEST_TMPDIR/out
  TUNNEL_NAME=mytunnel
  TUNNEL_CODE_STORAGE=$TEST_TMPDIR/storage
  TUNNEL_USER_PREFIX=$TEST_TMPDIR/user
  TUNNEL_GIST_FILE=$GIST
  TUNNEL_REEXPOSE=-
  TUNNEL_CODE_RESTART=0
  export FAKE_CALLS TUNNEL_NAME TUNNEL_CODE_STORAGE TUNNEL_USER_PREFIX \
    TUNNEL_GIST_FILE TUNNEL_REEXPOSE TUNNEL_CODE_RESTART
  : > "$FAKE_CALLS"

  fake_cmd code <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_CALLS"
if [ "$1 $2 $3" = "tunnel user login" ]; then
  echo "[2026-11-05 10:00:00] info To grant access to the server, please log into https://github.com/login/device and use code ABCD-1234"
  sleep 1
  exit "${FAKE_LOGIN_RC:-0}"
fi
n=$(grep -c '^tunnel --accept-server-license-terms' "$FAKE_CALLS")
if [ "$n" -le "${FAKE_FAILURES:-0}" ]; then
  echo "error connecting to tunnel: simulated failure $n"
  sleep 30
  exit 1
fi
echo "*"
echo "* Open this link in your browser https://vscode.dev/tunnel/run$n"
sleep 1
EOF
}

_logged_in() {
  mkdir -p "$TUNNEL_CODE_STORAGE"
  printf '{"token":"x"}\n' > "$TUNNEL_CODE_STORAGE/token.json"
}

_run() { run_script share/tunnels/code.sh "$@" > "$OUT" 2>&1; }

_tunnel_calls() { grep -c '^tunnel --accept-server-license-terms' "$FAKE_CALLS" || true; }

test_login_publishes_code_and_url() {
  _run
  gist=$(cat "$GIST")
  assert_contains "$gist" "requires device authorization at github"
  assert_contains "$gist" "https://github.com/login/device"
  assert_contains "$gist" "ABCD-1234"
  assert_contains "$gist" "https://vscode.dev/tunnel/run1"
  assert_true grep -q '^Last updated: ' "$GIST"
  assert_eq "tunnel user login --provider github
tunnel --accept-server-license-terms --name mytunnel" "$(cat "$FAKE_CALLS")"
}

test_login_leaves_no_watcher_behind() {
  [ -d /proc/self ] || skip "no /proc"
  _run
  assert_eq 0 "$(procs_matching "^tail .*code\.log")"
}

test_auth_code_publication_opt_out() {
  TUNNEL_CODE_AUTH_PUBLISH=0 _run
  assert_not_contains "$(cat "$GIST")" "ABCD-1234"
  assert_contains "$(cat "$GIST")" "https://vscode.dev/tunnel/run1" "URL still published"
  assert_contains "$(cat "$OUT")" "ABCD-1234" "code still in the container output"
}

test_logged_in_skips_login() {
  _logged_in
  _run
  assert_not_contains "$(cat "$FAKE_CALLS")" "user login"
  assert_not_contains "$(cat "$GIST")" "device authorization"
  assert_contains "$(cat "$GIST")" "https://vscode.dev/tunnel/run1"
}

test_force_login_when_logged_in() {
  _logged_in
  TUNNEL_FORCE=1 _run
  assert_contains "$(cat "$FAKE_CALLS")" "tunnel user login --provider github"
}

test_azure_provider() {
  _logged_in
  TUNNEL_FORCE=1 TUNNEL_PROVIDER=azure _run
  assert_contains "$(cat "$FAKE_CALLS")" "tunnel user login --provider azure"
}

test_restart_reuses_original_arguments() {
  _logged_in
  FAKE_FAILURES=1 _run --extra-arg value
  assert_eq 2 "$(_tunnel_calls)" "one failure, one restart, no extra tunnel"
  assert_eq 2 "$(grep -c -- '--name mytunnel --extra-arg value$' "$FAKE_CALLS")" "arguments on both runs"
  assert_eq 1 "$(grep -c 'vscode.dev/tunnel' "$GIST")" "only the URL of the restarted tunnel"
  assert_contains "$(cat "$GIST")" "https://vscode.dev/tunnel/run2"
  assert_contains "$(cat "$OUT")" "simulated failure 1"
}

test_single_tunnel_without_failures() {
  _logged_in
  _run
  assert_eq 1 "$(_tunnel_calls)"
}

test_random_name_without_tunnel_name() {
  _logged_in
  TUNNEL_NAME='' _run
  assert_contains "$(cat "$FAKE_CALLS")" "tunnel --accept-server-license-terms --random-name"
}

test_login_failure_stops() {
  rc=0
  FAKE_LOGIN_RC=3 _run || rc=$?
  assert_ne 0 "$rc" "exit code"
  assert_contains "$(cat "$OUT")" "Login at github failed with exit code 3"
  assert_eq 0 "$(_tunnel_calls)" "no tunnel started"
}

test_invalid_provider() {
  rc=0
  TUNNEL_PROVIDER=nowhere _run || rc=$?
  assert_ne 0 "$rc" "exit code"
  assert_contains "$(cat "$OUT")" "Invalid tunnel provider"
}

test_missing_cli_exits_quietly() {
  rm -f "$FAKEBIN/code"
  ! command -v code >/dev/null 2>&1 || skip "code installed on this system"
  _run
  assert_no_file "$GIST"
  assert_contains "$(cat "$OUT")" "Cannot find code"
}
