#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
LWRAP_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common; do
  for d in ../../lib ../lib lib; do
    if [ -d "${LWRAP_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${LWRAP_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done


# All following vars have defaults here, but will be set and inherited from
# the calling tunnel.sh script.
: "${LWRAP_VERBOSE:=0}"
: "${LWRAP_LOG:=2}"
: "${LWRAP_PREFIX:="${TUNNEL_PREFIX:-"/usr/local"}"}"

# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="Auto logger wrapper"
while getopts "vh-" opt; do
  case "$opt" in
    v) # Increase verbosity, repeat to increase
      LWRAP_VERBOSE=$((LWRAP_VERBOSE + 1));;
    h) # Show help
      usage 0 LWRAP
      ;;
    -) # End of options, file name to follow
      break;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done
shift $((OPTIND - 1))

[ -z "${1:-}" ] && error "No external process to wrap given"


# Initialize. Play ugly with the logging system to fake being the process that
# we are eating output from.
log_init LWRAP
unset CODER_BIN
bin_name "$1"

LWRAP_LOG="${LWRAP_PREFIX}/log/${CODER_BIN}.log"
_logline "" %s "$*" >>"$LWRAP_LOG"
exec "$@" >>"$LWRAP_LOG" 2>&1
