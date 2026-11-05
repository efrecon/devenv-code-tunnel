#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for lib/delegate.sh

setup() {
  load_lib log common system wait delegate
}

test_spawn_returns_pid_and_tracks_it() {
  make_script "$TEST_TMPDIR/sleeper.sh" <<'EOF'
#!/bin/sh
sleep 30
EOF
  spawn "$TEST_TMPDIR/sleeper.sh" > "$TEST_TMPDIR/pid"
  pid=$(cat "$TEST_TMPDIR/pid")
  assert_eq "$pid" "$(spawn_latest)"
  assert_true kill -0 "$pid"
  spawn_kill -r "test"
  spawn_wait || true
  assert_eq "" "$(spawn_latest)" "nothing left running"
}

test_spawn_requires_executable() {
  printf 'not executable\n' > "$TEST_TMPDIR/plain.sh"
  assert_fails spawn "$TEST_TMPDIR/plain.sh"
  assert_fails spawn
}

test_spawn_wait_returns_exit_code() {
  make_script "$TEST_TMPDIR/fail.sh" <<'EOF'
#!/bin/sh
exit 3
EOF
  spawn "$TEST_TMPDIR/fail.sh" > "$TEST_TMPDIR/pid"
  rc=0
  spawn_wait "$(cat "$TEST_TMPDIR/pid")" || rc=$?
  assert_eq 3 "$rc"
}

_sleepers() { procs_matching '^sleep 31'; }

test_spawn_kill_tree() {
  [ -d /proc/self ] || skip "no /proc"
  make_script "$TEST_TMPDIR/parent.sh" <<'EOF'
#!/bin/sh
sleep 31 &
wait
EOF
  spawn "$TEST_TMPDIR/parent.sh" >/dev/null
  pid=$(spawn_latest)
  wait_until 5 '[ "$(_sleepers)" -ge 1 ]'
  spawn_kill -t -r "test" "$pid"
  spawn_wait "$pid" || true
  wait_until 5 '[ "$(_sleepers)" -eq 0 ]'
}

test_spawn_logged_records_log_and_offset() {
  make_script "$TEST_TMPDIR/talker.sh" <<'EOF'
#!/bin/sh
echo "talking $1"
EOF
  lwrap=$(orchestration lwrap)
  spawn_logged -n talker "$lwrap" -- "$TEST_TMPDIR/talker.sh" first >/dev/null
  assert_eq "$TUNNEL_PREFIX/log/talker.log" "$_SPAWN_LOG"
  assert_eq 0 "$_SPAWN_LOG_OFFSET"
  spawn_wait "$(spawn_latest)"
  size=$(file_size "$_SPAWN_LOG")

  spawn_logged "$lwrap" -- "$TEST_TMPDIR/talker.sh" second >/dev/null
  assert_eq "$size" "$_SPAWN_LOG_OFFSET" "second run starts after the first"
  assert_eq "talking second" "$(when_infile "$_SPAWN_LOG_OFFSET" "$_SPAWN_LOG" E '^talking' -)"
  spawn_wait "$(spawn_latest)"
}

_init_dir() {
  mkdir -p "$TEST_TMPDIR/init"
  for s in 20-bar 10-foo 30-baz; do
    make_script "$TEST_TMPDIR/init/$s.sh" <<EOF
#!/bin/sh
echo "$s \$*" >> "$TEST_TMPDIR/ran"
EOF
  done
  printf '#!/bin/sh\n' > "$TEST_TMPDIR/init/40-notexec.sh"
}

test_init_list_and_get() {
  _init_dir
  assert_eq "foo bar baz " "$(init_list "$TEST_TMPDIR/init")"
  assert_eq "$TEST_TMPDIR/init/20-bar.sh" "$(init_get "$TEST_TMPDIR/init" bar)"
  assert_eq "" "$(init_get "$TEST_TMPDIR/init" notexec)"
}

test_delegate_runs_scripts_in_order() {
  _init_dir
  out=$(delegate "test" "$TEST_TMPDIR/init" "" "*.sh" 0 arg1)
  assert_eq "foo
bar
baz" "$out"
  assert_eq "10-foo arg1
20-bar arg1
30-baz arg1" "$(cat "$TEST_TMPDIR/ran")"
}

test_delegate_selected_and_disabled() {
  _init_dir
  assert_eq "baz" "$(delegate "test" "$TEST_TMPDIR/init" "baz")"
  assert_eq "" "$(delegate "test" "$TEST_TMPDIR/init" "-")"
  assert_eq "baz" "$(cat "$TEST_TMPDIR/ran" | cut -d' ' -f1 | sed 's/^30-//')"
}

test_delegate_fails_on_script_error() {
  mkdir -p "$TEST_TMPDIR/init"
  make_script "$TEST_TMPDIR/init/10-broken.sh" <<'EOF'
#!/bin/sh
exit 1
EOF
  assert_fails delegate "test" "$TEST_TMPDIR/init" "" "*.sh" 0
}

test_daemonize_restarts_in_background() {
  load_lib log common system wait delegate
  make_script "$TEST_TMPDIR/daemon.sh" <<EOF2
#!/bin/sh
set -eu
for lib in log common system delegate; do . "$PROJECT_ROOT/lib/\$lib.sh"; done
if [ -z "\${MYDAEMON_STARTED:-}" ]; then
  MYDAEMON_STARTED=\$\$
  echo "\$\$" > "$TEST_TMPDIR/foreground"
  daemonize MYDAEMON "\$@"
fi
echo "\$\$ \$MYDAEMON_STARTED \$*" > "$TEST_TMPDIR/background"
EOF2
  "$TEST_TMPDIR/daemon.sh" one two
  wait_until 5 '[ -s "$TEST_TMPDIR/background" ]'
  read -r bg_pid started args < "$TEST_TMPDIR/background" || true
  fg_pid=$(cat "$TEST_TMPDIR/foreground")
  assert_ne "$fg_pid" "$bg_pid" "runs in another process"
  assert_eq "$fg_pid" "$started" "prefixed variables exported"
  assert_eq "one two" "$(cut -d' ' -f3- "$TEST_TMPDIR/background")" "arguments passed"
}

test_delegate_in_background_with_supervise() {
  # delegate looks for supervise.sh relative to the calling script.
  mkdir -p "$TEST_TMPDIR/bin" "$TEST_TMPDIR/share" "$TEST_TMPDIR/init"
  ln -s "$PROJECT_ROOT/share/orchestration" "$TEST_TMPDIR/share/orchestration"
  for s in 10-first 20-second; do
    make_script "$TEST_TMPDIR/init/$s.sh" <<EOF2
#!/bin/sh
echo "$s \$*" > "$TEST_TMPDIR/$s.ran"
EOF2
  done
  make_script "$TEST_TMPDIR/bin/runner.sh" <<EOF2
#!/bin/sh
set -eu
for lib in log common system delegate; do . "$PROJECT_ROOT/lib/\$lib.sh"; done
delegate "test" "$TEST_TMPDIR/init" "" "*.sh" 1 arg
wait
EOF2
  out=$("$TEST_TMPDIR/bin/runner.sh")
  assert_match "$(printf '%s\n' "$out" | head -n 1)" "^first	[0-9]+$" "name and PID of supervisor"
  assert_match "$(printf '%s\n' "$out" | tail -n 1)" "^second	[0-9]+$"
  assert_eq "10-first arg" "$(cat "$TEST_TMPDIR/10-first.ran")"
  assert_eq "20-second arg" "$(cat "$TEST_TMPDIR/20-second.ran")"
}

test_spawn_logged_names_log_after_wrapped_command() {
  make_script "$TEST_TMPDIR/wrapper.sh" <<'EOF2'
#!/bin/sh
exec "$@"
EOF2
  make_script "$TEST_TMPDIR/talker.sh" <<'EOF2'
#!/bin/sh
echo "talking $1"
EOF2
  spawn_logged -n talker "$(orchestration lwrap)" -- "$TEST_TMPDIR/wrapper.sh" "$TEST_TMPDIR/talker.sh" wrapped >/dev/null
  assert_eq "$TUNNEL_PREFIX/log/talker.log" "$_SPAWN_LOG"
  assert_eq "talking wrapped" "$(when_infile "$_SPAWN_LOG_OFFSET" "$_SPAWN_LOG" E '^talking' -)"
  spawn_wait "$(spawn_latest)"
  assert_no_file "$TUNNEL_PREFIX/log/wrapper.log"
}
