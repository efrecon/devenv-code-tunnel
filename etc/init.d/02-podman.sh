#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
PODMAN_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find libraries
for lib in common cgroups; do
  for d in ../../lib ../lib lib; do
    if [ -d "${PODMAN_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${PODMAN_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at PODMAN_LOG.
: "${PODMAN_VERBOSE:=0}"

# Where to send logs
: "${PODMAN_LOG:=2}"

# Detach in the background
: "${PODMAN_DAEMONIZE:=0}"

# Prevent detaching in the background (RESERVED for use by the daemon)
: "${PODMAN_PREVENT_DAEMONIZATION:=0}"

: "${PODMAN_PREFIX:="/usr/local"}"




# shellcheck disable=SC2034 # Used from functions in common.sh
CODE_DESCR="Docker daemon startup"
while getopts "d:l:vh" opt; do
  case "$opt" in
    l) # Where to send logs
      PODMAN_LOG="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      PODMAN_VERBOSE=$((PODMAN_VERBOSE + 1));;
    h) # Show help
      usage 0 PODMAN
      ;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done

log_init PODMAN

# Only run if docker is present
if check_command podman; then
  # If we are to daemonize, do it now and exit. Export all our variables to the
  # daemon so it starts the same way this script was started.
  if ! is_true "$PODMAN_PREVENT_DAEMONIZATION" && is_true "$PODMAN_DAEMONIZE"; then
    # Do not daemonize the daemon!
    PODMAN_PREVENT_DAEMONIZATION=1
    PODMAN_DAEMONIZE=0
    daemonize_root PODMAN "$@"
  fi

  # All the following is running as root.
  cgroups_start
fi

