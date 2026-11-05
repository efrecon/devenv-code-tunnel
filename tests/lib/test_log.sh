#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for lib/log.sh

setup() {
  load_lib log common
}

test_cleanname() {
  assert_eq "lwrap" "$(cleanname /usr/local/share/orchestration/lwrap.sh)"
  assert_eq "sshd" "$(cleanname etc/init.d/20-sshd.sh)"
  assert_eq "codecli" "$(cleanname 10-install-codecli.sh)"
  assert_eq "tool" "$(cleanname tool)"
}

test_bin_name_sets_once() {
  unset CODER_BIN
  bin_name /some/path/01-myscript.sh
  assert_eq "myscript" "$CODER_BIN"
  bin_name /some/path/other.sh
  assert_eq "myscript" "$CODER_BIN" "should not be overridden"
}

test_colour_only_when_interactive() {
  CODER_INTERACTIVE=0
  assert_eq "plain" "$(red plain)"
  CODER_INTERACTIVE=1
  esc=$(printf '\033')
  assert_contains "$(red text)" "${esc}[1;31m"
}

test_log_disabled() {
  CODER_LOG=0
  assert_eq "" "$(warn "nothing" 2>&1)"
}

test_log_to_stdout_and_stderr() {
  CODER_LOG=1
  assert_contains "$(warn "to stdout %d" 42 2>/dev/null)" "to stdout 42"
  CODER_LOG=2
  assert_eq "" "$(warn "to stderr" 2>/dev/null)"
  assert_contains "$(warn "to stderr" 2>&1)" "to stderr"
}

test_log_line_format() {
  CODER_LOG=1
  CODER_BIN=mytag
  line=$(warn "hello")
  assert_match "$line" '^>+mytag<+ \[WRN\] \[[0-9]{8}-[0-9]{6}\] hello$'
}

test_log_to_file_without_colours() {
  CODER_LOG=$TEST_TMPDIR/out.log
  CODER_INTERACTIVE=1
  warn "first"
  warn "second"
  assert_eq 2 "$(wc -l < "$CODER_LOG" | tr -d ' ')"
  assert_contains "$(cat "$CODER_LOG")" "[WRN]"
  assert_not_contains "$(cat "$CODER_LOG")" "$(printf '\033')"
}

test_log_levels_follow_verbosity() {
  CODER_LOG=1
  CODER_VERBOSE=0
  assert_eq "" "$(verbose v; debug d; trace t)"
  CODER_VERBOSE=1
  assert_contains "$(verbose v; debug d)" "[NFO]"
  assert_not_contains "$(verbose v; debug d)" "[DBG]"
  CODER_VERBOSE=2
  assert_contains "$(debug d; trace t)" "[DBG]"
  assert_not_contains "$(debug d; trace t)" "[TRC]"
  CODER_VERBOSE=3
  assert_contains "$(trace t)" "[TRC]"
}

test_error_exits() {
  CODER_LOG=1
  out=$( (error "boom"; echo "not reached") || echo "exited $?")
  assert_contains "$out" "[ERR]"
  assert_contains "$out" "exited 1"
  assert_not_contains "$out" "not reached"
}

test_reprint_logs_and_appends_to_file() {
  CODER_LOG=1
  echo "existing" > "$TEST_TMPDIR/gist.txt"
  out=$(printf 'line one\nline two\n' | reprint "$TEST_TMPDIR/gist.txt")
  assert_contains "$out" "line one"
  assert_contains "$out" "line two"
  assert_eq "existing
line one
line two" "$(cat "$TEST_TMPDIR/gist.txt")"
}

test_gist_publish_timestamps_gist() {
  CODER_LOG=0
  make_script "$TEST_TMPDIR/timestamp.sh" <<EOF
#!/bin/sh
echo "\$*" > "$TEST_TMPDIR/timestamp.args"
EOF
  printf 'details\n' | gist_publish "$TEST_TMPDIR/gist.txt" "$TEST_TMPDIR/timestamp.sh"
  assert_eq "details" "$(cat "$TEST_TMPDIR/gist.txt")"
  assert_eq "-s 0 -- $TEST_TMPDIR/gist.txt" "$(cat "$TEST_TMPDIR/timestamp.args")"
}

test_gist_publish_without_gist_only_logs() {
  CODER_LOG=1
  make_script "$TEST_TMPDIR/timestamp.sh" <<EOF
#!/bin/sh
touch "$TEST_TMPDIR/timestamp.called"
EOF
  out=$(printf 'details\n' | gist_publish "" "$TEST_TMPDIR/timestamp.sh")
  assert_contains "$out" "details"
  assert_no_file "$TEST_TMPDIR/timestamp.called"
}

test_gist_publish_ignores_timestamp_failure() {
  CODER_LOG=0
  make_script "$TEST_TMPDIR/timestamp.sh" <<'EOF'
#!/bin/sh
exit 3
EOF
  printf 'details\n' | gist_publish "$TEST_TMPDIR/gist.txt" "$TEST_TMPDIR/timestamp.sh"
}

test_get_var() {
  # shellcheck disable=SC2034 # Read through get_var
  MY_VARIABLE="some value"
  assert_eq "some value" "$(get_var MY_VARIABLE)"
  assert_eq "" "$(get_var MY_UNSET_VARIABLE_XYZ 2>/dev/null)"
  _under_score1="ok"
  assert_eq "ok" "$(get_var _under_score1)"
}

test_get_var_rejects_invalid_names() {
  marker=$TEST_TMPDIR/injected
  for name in "" 1ABC "A-B" "A B" 'A}' 'X;touch $marker' "\$(touch $marker)" \
              "\`touch $marker\`" 'A:-$(touch x)'; do
    out=$(get_var "$name"; echo end)
    assert_eq "
end" "$out" "empty line for '$name'"
  done
  assert_no_file "$marker" "nothing executed"
}

test_log_init_from_prefixed_variables() {
  unset CODER_INTERACTIVE
  # shellcheck disable=SC2034 # Read through log_init
  MYAPP_VERBOSE=3
  # shellcheck disable=SC2034 # Read through log_init
  MYAPP_LOG=$TEST_TMPDIR/app.log
  log_init MYAPP
  assert_eq 3 "$CODER_VERBOSE"
  assert_eq "$TEST_TMPDIR/app.log" "$CODER_LOG"
  assert_eq 0 "$CODER_INTERACTIVE" "not a terminal"
}

test_log_init_defaults_to_bin_name() {
  CODER_BIN=myapp
  # shellcheck disable=SC2034 # Read through log_init
  MYAPP_VERBOSE=2
  # shellcheck disable=SC2034 # Read through log_init
  MYAPP_LOG=1
  log_init
  assert_eq 2 "$CODER_VERBOSE"
  assert_eq 1 "$CODER_LOG"
}
