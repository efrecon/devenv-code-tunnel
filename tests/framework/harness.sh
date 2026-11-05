#!/bin/sh

# Test harness: assertions and helpers available to all test files. This is
# sourced by exec.sh before the test file, and is not meant to be run directly.
#
# Conventions:
# - Assertions print a message on stderr and exit the test (a subprocess) with 1
#   when they fail.
# - skip exits the test with 77, which the runner reports as skipped.
# - Every test runs in a fresh, empty, temporary directory, which is also the
#   current directory and TMPDIR. It is available as TEST_TMPDIR, and removed
#   by the runner once the test has ended.
# - PROJECT_ROOT points to the root of the project, TESTS_ROOT to tests/.

# Source one or several libraries from the lib directory of the project, e.g.
# load_lib log common system
load_lib() {
  for _lib in "$@"; do
    # shellcheck disable=SC1090
    . "${PROJECT_ROOT}/lib/${_lib}.sh"
  done
  unset _lib
}

# Print the path to an orchestration script, e.g. "$(orchestration lwrap)"
orchestration() {
  printf '%s/share/orchestration/%s.sh\n' "$PROJECT_ROOT" "$1"
}

# Run an orchestration script with the shell under test, e.g.
# run_orchestration lwrap -L -- sh
run_orchestration() {
  _ro_script=$(orchestration "$1")
  shift
  # shellcheck disable=SC2086 # TESTS_SHELL can contain arguments, e.g. bash --posix
  ${TESTS_SHELL:-sh} "$_ro_script" "$@"
}

# Run a script of the project, relative to its root, with the shell under test,
# e.g. run_script share/tunnels/code.sh --some-arg
run_script() {
  _rs_script=${PROJECT_ROOT}/$1
  shift
  # shellcheck disable=SC2086 # TESTS_SHELL can contain arguments
  ${TESTS_SHELL:-sh} "$_rs_script" "$@"
}

# Restrict PATH to the system directories, preceded by FAKEBIN, a directory
# where fake_cmd creates fake commands. This keeps tools installed on the host
# (docker, gh, code, etc.) out of the way.
fake_path() {
  FAKEBIN=$TEST_TMPDIR/fakebin
  mkdir -p "$FAKEBIN"
  PATH=$FAKEBIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  export PATH FAKEBIN
}

# Create a fake command named $1 in FAKEBIN, with the content of stdin.
fake_cmd() {
  [ -n "${FAKEBIN:-}" ] || fake_path
  make_script "${FAKEBIN}/$1"
}

# Skip the test unless running as root, e.g. in the containers used at GitHub.
require_root() {
  [ "$(id -u)" = "0" ] || skip "requires root"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

skip() {
  printf 'SKIP: %s\n' "$*" >&2
  exit 77
}

# Skip the test when one of the commands passed as arguments is not available.
require_cmd() {
  for _cmd in "$@"; do
    command -v "$_cmd" >/dev/null 2>&1 || skip "$_cmd not available"
  done
  unset _cmd
}

# assert_eq <expected> <actual> [message]
assert_eq() {
  [ "$1" = "$2" ] || fail "${3:-"values differ"}: expected '$1', got '$2'"
}

# assert_ne <unexpected> <actual> [message]
assert_ne() {
  [ "$1" != "$2" ] || fail "${3:-"values are equal"}: did not expect '$1'"
}

# assert_match <actual> <extended regex> [message]
assert_match() {
  printf %s\\n "$1" | grep -qE -- "$2" || fail "${3:-"no match"}: '$1' does not match /$2/"
}

# assert_no_match <actual> <extended regex> [message]
assert_no_match() {
  if printf %s\\n "$1" | grep -qE -- "$2"; then
    fail "${3:-"unexpected match"}: '$1' matches /$2/"
  fi
}

# assert_contains <haystack> <fixed string> [message]
assert_contains() {
  printf %s\\n "$1" | grep -qF -- "$2" || fail "${3:-"not found"}: '$2' not in '$1'"
}

# assert_not_contains <haystack> <fixed string> [message]
assert_not_contains() {
  if printf %s\\n "$1" | grep -qF -- "$2"; then
    fail "${3:-"found"}: '$2' in '$1'"
  fi
}

# assert_true <command> [args...]: the command must succeed.
assert_true() {
  "$@" || fail "command failed: $*"
}

# assert_false <command> [args...]: the command must fail. Runs in a subshell,
# so commands calling exit (e.g. through error) are also caught.
assert_false() {
  if ( "$@" ) >/dev/null 2>&1; then
    fail "command succeeded: $*"
  fi
}

# assert_fails is an alias, reads better for functions that exit.
assert_fails() { assert_false "$@"; }

assert_file() {
  [ -f "$1" ] || fail "${2:-"missing file"}: $1"
}

assert_no_file() {
  [ ! -e "$1" ] || fail "${2:-"unexpected file"}: $1"
}

# wait_until <timeout in secs> <shell code>: evaluate the code until it
# succeeds, e.g. wait_until 5 '[ "$(count)" -ge 1 ]'. Pass the code in single
# quotes, so that it is evaluated at each try. Fails the test on timeout.
wait_until() {
  _wu_tries=$(( $1 * 10 ))
  shift
  while ! eval "$*" 2>/dev/null; do
    _wu_tries=$((_wu_tries - 1))
    [ "$_wu_tries" -le 0 ] && fail "timeout waiting for: $*"
    sleep 0.1
  done
  unset _wu_tries
}

# Count the processes which command line matches the extended regex passed as
# an argument. Uses /proc, as ps is not always available or compatible.
procs_matching() {
  _pm_count=0
  for _pm_f in /proc/[0-9]*/cmdline; do
    _pm_cmd=$(tr '\0' ' ' < "$_pm_f" 2>/dev/null) || continue
    if printf %s\\n "$_pm_cmd" | grep -qE -- "$1"; then
      _pm_count=$((_pm_count + 1))
    fi
  done
  printf %d\\n "$_pm_count"
  unset _pm_count _pm_f _pm_cmd
}

# Succeed when the process which PID is passed as an argument is running, i.e.
# exists and is not a zombie waiting to be reaped.
is_running() {
  [ -r "/proc/$1/stat" ] || return 1
  _ir_state=$(sed -E 's/^.*\) ([A-Za-z]).*$/\1/' "/proc/$1/stat" 2>/dev/null) || return 1
  [ -n "$_ir_state" ] && [ "$_ir_state" != "Z" ] && [ "$_ir_state" != "X" ]
}

is_stopped() { ! is_running "$1"; }

# Create an executable script at $1 with the content of stdin.
make_script() {
  cat > "$1"
  chmod a+x "$1"
}

# Make the library logging functions quiet and predictable by default. Tests
# about logging override these.
# shellcheck disable=SC2034 # Read by the libraries
{
  CODER_BIN="test"
  CODER_VERBOSE=0
  CODER_LOG=2
  CODER_INTERACTIVE=0
}
