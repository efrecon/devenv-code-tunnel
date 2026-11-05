#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for lib/common.sh

setup() {
  load_lib log common
}

test_to_lower_argument_and_stdin() {
  assert_eq "hello world" "$(to_lower "Hello WORLD")"
  assert_eq "abc" "$(printf 'ABC\n' | to_lower)"
}

test_to_upper_argument_and_stdin() {
  assert_eq "HELLO WORLD" "$(to_upper "Hello world")"
  assert_eq "ABC" "$(printf 'abc\n' | to_upper)"
}

test_is_true_accepts_true_values() {
  for v in 1 true TRUE yes Yes y on ON t; do
    assert_true is_true "$v"
  done
}

test_is_true_rejects_other_values() {
  for v in 0 false no off n "" 2 maybe; do
    assert_false is_true "$v"
  done
}

test_check_int_accepts_integers() {
  assert_true check_int 0 42 -7
}

test_check_int_rejects_non_integers() {
  assert_fails check_int 1.5
  assert_fails check_int 3 abc
  assert_fails check_int ""
}

test_assert_version() {
  assert_true assert_version 1
  assert_true assert_version 1.2.33
  assert_fails assert_version v1.2
  assert_fails assert_version 1.2-beta
}

test_generate_random_length_and_charset() {
  r=$(generate_random 12 'a-f')
  assert_match "$r" '^[a-f]{12}$'
  assert_eq 16 "$(generate_random | wc -c | tr -d ' ')" "default length"
}

test_generate_random_with_pipefail() {
  set -o | grep -q pipefail || skip "no pipefail in this shell"
  # A SIGPIPE in the pipeline is racy, try several times.
  # shellcheck disable=SC3040 # Only when supported, see above
  set -o pipefail
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    rc=0
    r=$(generate_random) || rc=$?
    assert_eq 0 "$rc" "exit code of generate_random with pipefail"
    assert_eq 16 "${#r}"
  done
}

test_find_inpath_prefers_path() {
  assert_eq "$(command -v sh)" "$(find_inpath sh /nonexistent)"
}

test_find_inpath_searches_prefixes() {
  mkdir -p "$TEST_TMPDIR/p1/bin" "$TEST_TMPDIR/p2/bin"
  printf '#!/bin/sh\n' | make_script "$TEST_TMPDIR/p2/bin/mytesttool"
  assert_eq "$TEST_TMPDIR/p2/bin/mytesttool" \
    "$(find_inpath mytesttool "$TEST_TMPDIR/p1" "$TEST_TMPDIR/p2/")"
}

test_find_inpath_missing_prints_nothing() {
  assert_eq "" "$(find_inpath mytesttool-nope "$TEST_TMPDIR" 2>/dev/null)"
}

test_find_exec_skips_self() {
  sh_path=$(command -v sh)
  assert_eq "$sh_path" "$(find_exec sh)"
  assert_eq "" "$(find_exec sh "$sh_path")"
  assert_eq "$sh_path" "$(find_exec sh /some/other/sh)"
}

test_export_varset_exports_prefixed_variables() {
  MYPFX_ONE=1
  MYPFX_TWO=two
  OTHER_ONE=x
  export_varset MYPFX
  # shellcheck disable=SC2016 # Expanded by the child shell
  assert_eq "1:two:" "$(sh -c 'echo "${MYPFX_ONE:-}:${MYPFX_TWO:-}:${OTHER_ONE:-}"')"
}

test_varset_without_matching_variables() {
  export_varset NOSUCHPREFIX
  unset_varset NOSUCHPREFIX
}

test_export_varset_keeps_values_intact() {
  MYPFX_with_lower2='a value with spaces'
  MYPFX_X2="it's quoted"
  export_varset MYPFX
  assert_eq "a value with spaces|it's quoted" \
    "$(sh -c 'echo "${MYPFX_with_lower2:-}|${MYPFX_X2:-}"')"
  unset_varset MYPFX
  assert_eq "|" "${MYPFX_with_lower2:-}|${MYPFX_X2:-}"
}

test_unset_varset_unsets_prefixed_variables() {
  MYPFX_ONE=1
  MYPFX_TWO=2
  OTHER_ONE=x
  unset_varset MYPFX
  assert_eq "::x" "${MYPFX_ONE:-}:${MYPFX_TWO:-}:${OTHER_ONE:-}"
}

# Fail as many times as the content of the counter file, then succeed.
_flaky() {
  n=$(cat "$TEST_TMPDIR/count")
  if [ "$n" -gt 0 ]; then
    printf %d\\n "$((n - 1))" > "$TEST_TMPDIR/count"
    return 1
  fi
  return 0
}

test_retry_until_success() {
  echo 2 > "$TEST_TMPDIR/count"
  retry -m 5 -w 0 _flaky
  assert_eq 0 "$(cat "$TEST_TMPDIR/count")"
}

test_retry_gives_up() {
  echo 10 > "$TEST_TMPDIR/count"
  assert_fails retry -m 3 -w 0 _flaky
}

test_read_envfile_sources_and_reinits_logging() {
  cat > "$TEST_TMPDIR/test.env" <<'EOF'
MYAPP_VERBOSE=2
MYAPP_LOG=1
MYAPP_VALUE="from file"
EOF
  read_envfile "$TEST_TMPDIR/test.env" MYAPP
  assert_eq "from file" "$MYAPP_VALUE"
  assert_eq 2 "$CODER_VERBOSE"
  assert_eq 1 "$CODER_LOG"
}

test_read_envfile_missing_file_is_ignored() {
  assert_true read_envfile "$TEST_TMPDIR/missing.env" MYAPP
}
