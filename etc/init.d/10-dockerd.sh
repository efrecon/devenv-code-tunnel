#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
DOCKERD_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )
for lib in common system docker; do
  for d in ../../lib ../lib lib; do
    if [ -d "${DOCKERD_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${DOCKERD_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Arrange to set the CODER_BIN variable to the name of the script
bin_name


# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at DOCKERD_LOG.
: "${DOCKERD_VERBOSE:="${TUNNEL_VERBOSE:-"0"}"}"

# Where to send logs
: "${DOCKERD_LOG:="${TUNNEL_LOG:-"2"}"}"

: "${DOCKERD_PREFIX:="${TUNNEL_PREFIX:-"/usr/local"}"}"

# Where the docker daemon listens, defaults to the standard docker socket.
: "${DOCKERD_SOCK:="/var/run/docker.sock"}"

# Environment file to load for reading defaults from.
: "${DOCKERD_DEFAULTS:="${DOCKERD_ROOTDIR}/../${CODER_BIN}.env"}"

# Detach in the background
: "${DOCKERD_DAEMONIZE:=0}"

# Prevent detaching in the background (RESERVED for use by the daemon)
: "${_DOCKERD_PREVENT_DAEMONIZATION:=0}"


# shellcheck disable=SC2034 # Used from functions in common.sh
CODE_DESCR="Docker daemon startup"
while getopts "l:vh" opt; do
  case "$opt" in
    l) # Where to send logs
      DOCKERD_LOG="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      DOCKERD_VERBOSE=$((DOCKERD_VERBOSE + 1));;
    h) # Show help
      usage 0 DOCKERD
      ;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done

log_init DOCKERD

# Load defaults
[ -n "$DOCKERD_DEFAULTS" ] && read_envfile "$DOCKERD_DEFAULTS" DOCKERD


dockerd_start() {
  as_root dockerd 2>&1 | tee -a "$DOCKERD_LOGFILE" > /dev/null &
}

dockerd_wait() {
  while true; do
    if curl --head --unix-socket "$DOCKERD_SOCK" http://localhost/_ping 2>/dev/null | grep -q 'HTTP/1.1 200 OK'; then
      break
    fi
    sleep 1
  done
}

if as_root test -S "$DOCKERD_SOCK"; then
  # Docker is already running, so we don't need to start it again.
  verbose "Docker daemon already running."
  exit 0
fi

if ! check_command "dockerd"; then
  exit 0
fi

if ! is_privileged; then
  warn "DinD can only be run in a privileged container."
  exit 0
fi

# If we are to daemonize, do it now and exit. Export all our variables to the
# daemon so it starts the same way this script was started.
if ! is_true "$_DOCKERD_PREVENT_DAEMONIZATION" && is_true "$DOCKERD_DAEMONIZE"; then
  # Do not daemonize the daemon!
  _DOCKERD_PREVENT_DAEMONIZATION=1
  DOCKERD_DAEMONIZE=0
  daemonize DOCKERD "$@"
fi

DOCKERD_LOGFILE="${DOCKERD_PREFIX}/log/dockerd.log"
dockerd_start
dockerd_wait
if [ -z "$TUNNEL_REEXPOSE" ] || printf %s\\n "$TUNNEL_REEXPOSE" | grep -qF 'dockerd'; then
  verbose "Docker daemon responding on socket %s, forwarding logs from %s" "$DOCKERD_SOCK" "$DOCKERD_LOGFILE"
  "${DOCKERD_ROOTDIR}/../../share/orchestration/logger.sh" -s "dockerd" -- "$DOCKERD_LOGFILE" &
else
  verbose "Docker daemon responding on socket %s, logs at %s" "$DOCKERD_SOCK" "$DOCKERD_LOGFILE"
fi
