#!/bin/sh

# Run a single test function from a test file. Called by run.sh, in the
# temporary directory of the test.
# $1: path to the test file
# $2: name of the test function to run

set -eu

TESTS_ROOT=$( cd -P -- "$(dirname -- "$0")/.." && pwd -P )
PROJECT_ROOT=$( cd -P -- "${TESTS_ROOT}/.." && pwd -P )
TEST_TMPDIR=$(pwd -P)
TMPDIR=$TEST_TMPDIR
export TESTS_ROOT PROJECT_ROOT TEST_TMPDIR TMPDIR

# Isolate from the environment of the caller as much as possible: no inherited
# tunnel settings, and logs from the orchestration scripts end up in the test
# directory.
unset_prefix() {
  for _var in $(set | grep -E "^${1}_[A-Za-z0-9_]*=" | sed -E 's/=.*//'); do
    unset "$_var"
  done
}
unset_prefix TUNNEL
unset_prefix CODER
TUNNEL_PREFIX=$TEST_TMPDIR/prefix
export TUNNEL_PREFIX

# shellcheck source=tests/framework/harness.sh
. "${TESTS_ROOT}/framework/harness.sh"
# shellcheck disable=SC1090
. "$1"

if command -v setup >/dev/null 2>&1; then setup; fi
"$2"
