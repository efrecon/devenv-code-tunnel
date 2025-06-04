#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
LWRAP_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common; do
  for d in ../../lib ../lib lib; do
    if [ -d "${LWRAP_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${LWRAP_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Arrange to set the CODER_BIN variable to the name of the script
bin_name


# All following vars have defaults here, but will be set and inherited from
# the calling tunnel.sh script.
: "${LWRAP_VERBOSE:=0}"
: "${LWRAP_LOG:=2}"
: "${LWRAP_PREFIX:="${TUNNEL_PREFIX:-"/usr/local"}"}"
: "${LWRAP_PRINT:=0}"
# Environment file to load for reading defaults from.
: "${LWRAP_DEFAULTS:="${LWRAP_ROOTDIR}/../../etc/${CODER_BIN}.env"}"


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="Auto logger wrapper"
while getopts "Lvh-" opt; do
  case "$opt" in
    L) # Print target log file and exit
      LWRAP_PRINT=1;;
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
# Load defaults
[ -n "$LWRAP_DEFAULTS" ] && read_envfile "$LWRAP_DEFAULTS" LWRAP
unset CODER_BIN
bin_name "$1"

# Decide upon location of log
LWRAP_LOG="${LWRAP_PREFIX}/log/${CODER_BIN}.log"
if ! [ -d "${LWRAP_PREFIX}/log" ]; then
  debug "Creating log directory %s" "${LWRAP_PREFIX}/log"
  mkdir -p "${LWRAP_PREFIX}/log"
fi

# Print log location and exit when flag is set.
if [ "$LWRAP_PRINT" = "1" ]; then
  printf %s\\n "$LWRAP_LOG"
  exit
fi

# Reprint command, then send all lines to log
_logline "" %s "$*" >>"$LWRAP_LOG"
# TODO: Should we forward into logger.sh? Make it configuration, as some tools might timestamp?
exec "$@" >>"$LWRAP_LOG" 2>&1
