#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
SERVICES_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common system; do
  for d in ../../lib ../lib lib; do
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

# List of services to start. When empty, all services will be started.
: "${SERVICES_SERVICES:=""}"

# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="Start services"
while getopts "s:l:vh" opt; do
  case "$opt" in
    s) # List of services to start
      SERVICES_SERVICES="$OPTARG";;
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

if [ -z "$SERVICES_SERVICES" ]; then
  SERVICES_SERVICES=$(init_list "$SERVICES_DIR" '??-*.sh')
  verbose "Running all services: %s" "$SERVICES_SERVICES"
fi

for svc in $SERVICES_SERVICES; do
  script=$(init_get "$SERVICES_DIR" "$svc")
  if [ -z "$script" ]; then
    warn "Service %s not found in %s" "$svc" "$SERVICES_DIR"
    continue
  fi
  if [ -x "$script" ]; then
    verbose "Starting %s using %s" "$svc" "$script"
    "$script"
  fi
done
