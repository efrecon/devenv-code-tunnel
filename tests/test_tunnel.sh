#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the scripts and in wait_until
# Tests for tunnel.sh, the entrypoint. Run without services nor tunnels, with a
# local bare repository standing in for the gist at GitHub.

setup() {
  require_cmd git
  load_lib log common system
  fake_path
  # Isolate from the git configuration of the user (signing, hooks, etc.).
  HOME=$TEST_TMPDIR/home
  mkdir -p "$HOME"
  GIT_CONFIG_NOSYSTEM=1
  GIT_AUTHOR_NAME=Tester
  GIT_AUTHOR_EMAIL=tester@example.com
  GIT_COMMITTER_NAME=Tester
  GIT_COMMITTER_EMAIL=tester@example.com
  export HOME GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

  ORIGIN=$TEST_TMPDIR/origin.git
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$TEST_TMPDIR/init" 2>/dev/null
  printf 'init\n' > "$TEST_TMPDIR/init/README"
  git -C "$TEST_TMPDIR/init" add README
  git -C "$TEST_TMPDIR/init" commit -q -m "init"
  git -C "$TEST_TMPDIR/init" push -q -u origin HEAD 2>/dev/null

  # tunnel.sh restarts itself as another user when run as root, as in the
  # containers used at GitHub. Pretend not to be root.
  if [ "$(id -u)" = "0" ]; then
    fake_cmd id <<'EOF'
#!/bin/sh
case "$*" in
  -u) echo 1000;;
  -un) echo tester;;
  *) exec /usr/bin/id "$@";;
esac
EOF
  fi
  OUT=$TEST_TMPDIR/out
}

# Processes started for the gist: they work on files in the test directory.
_gist_processes() {
  procs_matching "(timestamp|notify)\.sh .*${TEST_TMPDIR}"
}

_start() {
  # Not through a function such as run_script: in the background, some shells
  # would fork a subshell waiting for tunnel.sh, and $! would be that subshell.
  # shellcheck disable=SC2086 # TESTS_SHELL can contain arguments
  ${TESTS_SHELL:-sh} "$PROJECT_ROOT/tunnel.sh" -S - -T - -n smoketest -G "$ORIGIN" > "$OUT" 2>&1 &
  TUNNEL_PID=$!
  wait_until 30 '[ "$(_gist_processes)" -ge 2 ]'
}

test_signal_stops_gist_processes() {
  [ -d /proc/self ] || skip "no /proc"
  sleepers=$(procs_matching '^sleep 86400')
  _start
  kill -TERM "$TUNNEL_PID"
  wait "$TUNNEL_PID" 2>/dev/null || true
  wait_until 10 '[ "$(_gist_processes)" -eq 0 ]'
  assert_eq 0 "$(procs_matching "inotifywait .*${TEST_TMPDIR}")" "notify.sh children"
  wait_until 10 '[ "$(procs_matching "^sleep 86400")" -le "$sleepers" ]'
}

# Is the idle loop of tunnel.sh sleeping? Its sleep is a child of tunnel.sh.
_idle_sleep() {
  for _p in $(ps_children "$TUNNEL_PID" 2>/dev/null); do
    tr '\0' ' ' < "/proc/$_p/cmdline" 2>/dev/null | grep -q '^sleep 5 *$' && return 0
  done
  return 1
}

test_signal_handled_without_delay() {
  [ -d /proc/self ] || skip "no /proc"
  _start
  # Signal while the idle loop has just started sleeping, i.e. worst case.
  wait_until 15 '_idle_sleep'
  start=$(date +%s)
  kill -TERM "$TUNNEL_PID"
  wait "$TUNNEL_PID" 2>/dev/null || true
  elapsed=$(( $(date +%s) - start ))
  [ "$elapsed" -le 2 ] || fail "tunnel.sh took ${elapsed}s to stop"
}

# No test for INT: a non-interactive shell starts background jobs with INT
# ignored, and a signal ignored at startup cannot be trapped.

test_gist_file_cloned_and_named_after_tunnel() {
  [ -d /proc/self ] || skip "no /proc"
  _start
  # timestamp.sh creates the file
  wait_until 10 '[ -n "$(find "$TEST_TMPDIR" -maxdepth 2 -path "*gist-*/smoketest.txt")" ]'
  gist=$(find "$TEST_TMPDIR" -maxdepth 2 -path '*gist-*/smoketest.txt')
  assert_match "$(cat "$gist")" '^Last updated: '
  kill -TERM "$TUNNEL_PID"
  wait "$TUNNEL_PID" 2>/dev/null || true
}
