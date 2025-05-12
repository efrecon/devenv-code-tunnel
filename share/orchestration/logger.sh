#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
LOGGER_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common system; do
  for d in ../../lib ../lib lib; do
    if [ -d "${LOGGER_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${LOGGER_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done


# All following vars have defaults here, but will be set and inherited from
# the calling tunnel.sh script.
: "${LOGGER_VERBOSE:=0}"
: "${LOGGER_LOG:=2}"

: "${LOGGER_SOURCE:=""}"

# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="re-logger"
while getopts "s:vh-" opt; do
  case "$opt" in
    s) # source of the log file to follow
      LOGGER_SOURCE="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      LOGGER_VERBOSE=$((LOGGER_VERBOSE + 1));;
    h) # Show help
      usage 0 LOGGER
      ;;
    -) # End of options, file name to follow
      break;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done
shift $((OPTIND - 1))


# Initialize. Play ugly with the logging system to fake being the process that
# we are eating output from.
log_init LOGGER
unset CODER_BIN
bin_name "$LOGGER_SOURCE"

# Remove existing log line header from our logs
no_header() {
  if [ -n "${1:-}" ]; then
    printf %s\\n "$1" | no_header
  else
    sed -E 's/^>[><a-z-]+< \[[A-Z]+\] \[[0-9-]+\] //g'
  fi
}

# Eat lines and reprint them through our logging library, adding a header.
relog() {
  while IFS= read -r line; do
    _log "" "$(no_header "$line")"
  done
}

if [ -z "${1:-}" ]; then
  relog
else
  # Eagerly wait for the log file to exist
  while ! [ -f "$1" ]; do sleep 0.1; done
  debug "$1 now present on disk"

  tail -n +0 -F "$1" | relog
fi
