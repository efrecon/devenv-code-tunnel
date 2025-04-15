#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
DOCKERD_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common docker; do
  for d in ../../lib ../lib lib; do
    if [ -d "${DOCKERD_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1091 source=lib/common.sh
      . "${DOCKERD_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at DOCKERD_LOG.
: "${DOCKERD_VERBOSE:=0}"

# Where to send logs
: "${DOCKERD_LOG:=2}"

# Detach in the background
: "${DOCKERD_DAEMONIZE:=0}"

# Prevent detaching in the background (RESERVED for use by the daemon)
: "${DOCKERD_PREVENT_DAEMONIZATION:=0}"

: "${DOCKERD_PREFIX:="/usr/local"}"




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

if ! is_privileged; then
  warn "DinD can only be run in a privileged container."
  exit 0
fi

# If we are to daemonize, do it now and exit. Export all our variables to the
# daemon so it starts the same way this script was started.
if ! is_true "$DOCKERD_PREVENT_DAEMONIZATION" && is_true "$DOCKERD_DAEMONIZE"; then
  # Do not daemonize the daemon!
  DOCKERD_PREVENT_DAEMONIZATION=1
  DOCKERD_DAEMONIZE=0
  daemonize DOCKERD "$@"
fi

as_root dockerd 2>&1 | tee -a "${DOCKERD_PREFIX}/log/dockerd.log" > /dev/null &
