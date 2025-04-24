#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
SERVICES_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common system; do
  for d in ../lib lib; do
    if [ -d "${SERVICES_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${SERVICES_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done


# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at SERVICES_LOG.
: "${SERVICES_VERBOSE:=0}"

# Where to send logs
: "${SERVICES_LOG:=2}"

: "${SERVICES_PREFIX:="/usr/local"}"

# Where to find the services
: "${SERVICES_DIR:="${SERVICES_PREFIX}/etc/init.d"}"

# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="Start services"
while getopts "l:n:vh" opt; do
  case "$opt" in
    l) # Where to send logs
      SERVICES_LOG="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      SERVICES_VERBOSE=$((SERVICES_VERBOSE + 1));;
    h) # Show help
      usage 0 SERVICES
      ;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done

# Initialize
log_init SERVICES


for svc in "${SERVICES_DIR%/}"/*.sh; do
  if [ -f "$svc" ]; then
    if ! [ -x "$svc" ]; then
      debug "Making $svc executable"
      chmod a+x "$svc"
    fi
    verbose "Starting $svc"
    "$svc"
  fi
done
