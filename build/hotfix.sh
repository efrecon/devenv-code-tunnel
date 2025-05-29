#!/bin/sh

# This script is used to apply hotfixes.

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
HOTFIX_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log; do
  for d in ../lib lib; do
    if [ -d "${HOTFIX_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${HOTFIX_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done


# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at HOTFIX_LOG.
: "${HOTFIX_VERBOSE:=0}"

# Where to send logs
: "${HOTFIX_LOG:=2}"

# Location of the docker init.d script
: "${HOTFIX_DOCKER_INITD:=/etc/init.d/docker}"


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="Hotfix docker installation"
while getopts "l:vh" opt; do
  case "$opt" in
    l) # Where to send logs
      HOTFIX_LOG="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      HOTFIX_VERBOSE=$((HOTFIX_VERBOSE + 1));;
    h) # Show help
      usage 0 HOTFIX
      ;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done

log_init HOTFIX

if [ -n "$HOTFIX_DOCKER_INITD" ]; then
  if [ -f "$HOTFIX_DOCKER_INITD" ]; then
    # Ensure docker can be started! See:
    # https://forums.docker.com/t/etc-init-d-docker-62-ulimit-error-setting-limit-invalid-argument-problem/139424
    verbose "Fix ulimit in docker init.d script at $HOTFIX_DOCKER_INITD"
    sed -i 's/ulimit -Hn 524288/ulimit -n 524288/g' "$HOTFIX_DOCKER_INITD"
  else
    warn "Docker init.d script not found at $HOTFIX_DOCKER_INITD"
  fi
fi