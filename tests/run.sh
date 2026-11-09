#!/bin/sh

# Run the unit tests. Each test function (test_*) of each test file (test_*.sh)
# runs in a separate shell process, in its own temporary directory.
#
# Usage: tests/run.sh [-s shell] [-t timeout] [-v] [filter...]
# Filters are extended regular expressions matched against
# <file>:<function>, e.g. tests/run.sh wait: 'lwrap.*:test_print'

set -eu

TESTS_ROOT=$( cd -P -- "$(dirname -- "$0")" && pwd -P )

: "${TESTS_SHELL:="sh"}"
: "${TESTS_TIMEOUT:="60"}"
: "${TESTS_VERBOSE:="0"}"

usage() {
  sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'
  printf '\n  -s  shell to run tests with, may contain arguments, e.g. "bash --posix" (default: %s)\n' "$TESTS_SHELL"
  printf '  -t  timeout per test, in seconds (default: %s)\n' "$TESTS_TIMEOUT"
  printf '  -v  print the output of all tests, not only failed ones\n'
  exit "${1:-0}"
}

while getopts "s:t:vh" opt; do
  case "$opt" in
    s) TESTS_SHELL=$OPTARG;;
    t) TESTS_TIMEOUT=$OPTARG;;
    v) TESTS_VERBOSE=1;;
    h) usage 0;;
    *) usage 1;;
  esac
done
shift $((OPTIND - 1))
# Tests run orchestration scripts with the same shell.
export TESTS_SHELL

# Run with a timeout when possible, tests waiting on processes could hang.
if command -v timeout >/dev/null 2>&1; then
  _timeout="timeout $TESTS_TIMEOUT"
else
  _timeout=
fi

# Does <file>:<function> match one of the filters given on the command line?
selected() {
  [ "$#" -le 1 ] && return 0
  _id=$1
  shift
  for _filter in "$@"; do
    if printf %s\\n "$_id" | grep -qE -- "$_filter"; then
      return 0
    fi
  done
  return 1
}

indent() { sed 's/^/    /'; }

_passed=0
_failed=0
_skipped=0
_failures=
_workdir=$(mktemp -d "${TMPDIR:-/tmp}/tests.XXXXXX")
trap 'rm -rf "$_workdir"' EXIT

# TESTS_SHELL can contain arguments, e.g. "bash --posix", hence no quotes.
# shellcheck disable=SC2086
_shell_path=$(command -v ${TESTS_SHELL%% *} || echo "?")
# Report when bash runs in POSIX mode, SHELLOPTS is for the tested shell.
# shellcheck disable=SC2086,SC2016
if $TESTS_SHELL -c 'case "${SHELLOPTS:-}" in *posix*) exit 0;; *) exit 1;; esac' 2>/dev/null; then
  _shell_path="$_shell_path, bash POSIX mode"
fi
printf 'Running tests with %s (%s)\n' "$TESTS_SHELL" "$_shell_path"
for _file in $(find "$TESTS_ROOT" -type f -name 'test_*.sh' | sort); do
  _rel=${_file#"${TESTS_ROOT}/"}
  # shellcheck disable=SC2013 # Function names have no spaces
  for _fn in $(grep -oE '^test_[A-Za-z0-9_]+\(\)' "$_file" | sed 's/()$//'); do
    selected "${_rel}:${_fn}" "$@" || continue

    # Fresh directory for each test, removed afterwards whatever happens.
    _tmp=$(mktemp -d "${_workdir}/t.XXXXXX")
    _out=${_workdir}/output
    _rc=0
    # shellcheck disable=SC2086 # TESTS_SHELL can contain arguments
    ( cd "$_tmp" && $_timeout $TESTS_SHELL "${TESTS_ROOT}/framework/exec.sh" "$_file" "$_fn" ) \
      >"$_out" 2>&1 </dev/null || _rc=$?
    rm -rf "$_tmp"

    case "$_rc" in
      0)
        _passed=$((_passed + 1))
        printf 'ok      %s:%s\n' "$_rel" "$_fn"
        [ "$TESTS_VERBOSE" = "1" ] && indent < "$_out"
        ;;
      77)
        _skipped=$((_skipped + 1))
        printf 'skip    %s:%s (%s)\n' "$_rel" "$_fn" "$(grep '^SKIP: ' "$_out" | tail -n 1 | sed 's/^SKIP: //')"
        ;;
      *)
        _failed=$((_failed + 1))
        _failures="${_failures}  ${_rel}:${_fn}
"
        [ "$_rc" = "124" ] && echo "Timed out after ${TESTS_TIMEOUT}s" >> "$_out"
        printf 'not ok  %s:%s (exit code %d)\n' "$_rel" "$_fn" "$_rc"
        indent < "$_out"
        ;;
    esac
  done
done

printf '\n%d passed, %d failed, %d skipped\n' "$_passed" "$_failed" "$_skipped"
if [ "$_failed" -gt 0 ]; then
  printf 'Failed tests:\n%s' "$_failures"
  exit 1
fi
