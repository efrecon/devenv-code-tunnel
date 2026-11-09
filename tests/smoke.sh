#!/bin/sh

# Smoke test of a built image: start a container without tunnels, check that
# the services started, that it runs as the expected user, that nothing logged
# an error, and that it stops gracefully.
#
# Usage: tests/smoke.sh [-t timeout] [-u user] <image>

set -eu

: "${SMOKE_TIMEOUT:="180"}"
: "${SMOKE_USER:="coder"}"
: "${SMOKE_SSH:="2222"}"
: "${SMOKE_ORCHESTRATOR:="docker"}"

while getopts "t:u:h" opt; do
  case "$opt" in
    t) SMOKE_TIMEOUT=$OPTARG;;
    u) SMOKE_USER=$OPTARG;;
    h) sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) exit 1;;
  esac
done
shift $((OPTIND - 1))
[ -z "${1:-}" ] && { echo "No image given" >&2; exit 1; }
SMOKE_IMAGE=$1

SMOKE_NAME=devenv-smoke-$$
_failed=0

say() { printf '%s\n' "$*" >&2; }
ok() { say "ok      $*"; }
not_ok() { say "not ok  $*"; _failed=1; }

cleanup() {
  if [ "$_failed" = "1" ]; then
    say "--- Container logs:"
    "$SMOKE_ORCHESTRATOR" logs "$SMOKE_NAME" 2>&1 | tail -n 100 >&2 || true
  fi
  "$SMOKE_ORCHESTRATOR" rm -f "$SMOKE_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

in_container() { "$SMOKE_ORCHESTRATOR" exec "$SMOKE_NAME" sh -c "$1"; }

running() {
  [ "$("$SMOKE_ORCHESTRATOR" inspect -f '{{.State.Running}}' "$SMOKE_NAME" 2>/dev/null)" = "true" ]
}

# Is something listening on the port passed as an argument, inside the
# container? Read /proc, as nc or ss are not in all images.
listening() {
  _port=$(printf '%04X' "$1")
  in_container "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null" |
    grep -qE "^ *[0-9]+: [0-9A-F]+:${_port} [0-9A-F]+:[0-9A-F]+ 0A "
}

# No --hostname: like a plain run, the hostname is a container ID and a random
# tunnel name gets generated. Default verbosity, as most users would.
say "Starting $SMOKE_IMAGE as $SMOKE_NAME, without tunnels"
"$SMOKE_ORCHESTRATOR" run -d --name "$SMOKE_NAME" "$SMOKE_IMAGE" -T - >/dev/null

# Services start in the foreground, one after the other. sshd is one of them.
_waited=0
while ! listening "$SMOKE_SSH"; do
  if ! running; then
    not_ok "container exited before sshd started"
    exit 1
  fi
  if [ "$_waited" -ge "$SMOKE_TIMEOUT" ]; then
    not_ok "sshd listening on port $SMOKE_SSH within ${SMOKE_TIMEOUT}s"
    exit 1
  fi
  sleep 2
  _waited=$((_waited + 2))
done
ok "sshd listening on port $SMOKE_SSH after ~${_waited}s"

# Give the remaining services some time to start.
sleep 10
if running; then ok "container running"; else not_ok "container running"; fi

_user=$(in_container 'id -un')
if [ "$_user" = "$SMOKE_USER" ]; then
  ok "running as $SMOKE_USER"
else
  not_ok "running as $SMOKE_USER, not $_user"
fi

for _cmd in tunnel.sh code git; do
  if in_container "command -v $_cmd" >/dev/null; then
    ok "$_cmd available"
  else
    not_ok "$_cmd available"
  fi
done

_errors=$("$SMOKE_ORCHESTRATOR" logs "$SMOKE_NAME" 2>&1 | grep -F '[ERR]' || true)
if [ -z "$_errors" ]; then
  ok "no errors in logs"
else
  not_ok "no errors in logs:"
  printf '%s\n' "$_errors" | sed 's/^/    /' >&2
fi

# Stop gracefully, i.e. before the orchestrator resorts to killing.
_start=$(date +%s)
"$SMOKE_ORCHESTRATOR" stop -t 30 "$SMOKE_NAME" >/dev/null
_elapsed=$(( $(date +%s) - _start ))
if [ "$_elapsed" -lt 30 ]; then
  ok "stopped gracefully in ${_elapsed}s"
else
  not_ok "stopped gracefully, had to be killed after ${_elapsed}s"
fi

[ "$_failed" = "0" ] || exit 1
say "All smoke tests passed"
