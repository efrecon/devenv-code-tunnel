#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
TIMESTAMP_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common system; do
  for d in ../../lib ../lib lib; do
    if [ -d "${TIMESTAMP_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${TIMESTAMP_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Arrange to set the CODER_BIN variable to the name of the script
bin_name


# All following vars have defaults here, but will be set and inherited from
# the calling tunnel.sh script.
: "${TIMESTAMP_VERBOSE:="${TUNNEL_VERBOSE:-"0"}"}"
: "${TIMESTAMP_LOG:="${TUNNEL_LOG:-"2"}"}"

: "${TIMESTAMP_PATH:=""}"
: "${TIMESTAMP_SLEEP:="86400"}"
: "${TIMESTAMP_HEADER:="Last updated: "}"
# Environment file to load for reading defaults from.
: "${TIMESTAMP_DEFAULTS:="${TIMESTAMP_ROOTDIR}/../../etc/${CODER_BIN}.env"}"


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="Timestamp file at regular intervals, or once."
while getopts "H:s:vh-" opt; do
  case "$opt" in
    H) # Header to use in the timestamp file. Default: "Last updated: "
      TIMESTAMP_HEADER="$OPTARG";;
    s) # Sleep interval, in secs, between updates. 0 to update once only. Default every 24 hours.
      TIMESTAMP_SLEEP="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      TIMESTAMP_VERBOSE=$((TIMESTAMP_VERBOSE + 1));;
    h) # Show help
      usage 0 TIMESTAMP
      ;;
    -) # End of options, file name to follow
      break;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done
shift $((OPTIND - 1))


timestamp_set() {
  _timestamp=$(date '+%Y%m%d-%H%M%S%z')
  # Ensure that the header is escaped properly for use in regex and replacement in sed.
  _timestamp_header_regex=$(printf '%s\n' "$TIMESTAMP_HEADER" | sed 's/[][\\.^$*]/\\&/g')
  _timestamp_header_replacement=$(printf '%s\n' "$TIMESTAMP_HEADER" | sed 's/[\\&|]/\\&/g')

  if grep -q "^${_timestamp_header_regex}" "$TIMESTAMP_PATH"; then
    verbose "Updating timestamp in %s" "$TIMESTAMP_PATH"
    sed -i "s|^${_timestamp_header_regex}.*|${_timestamp_header_replacement}${_timestamp}|" "$TIMESTAMP_PATH"
  else
    verbose "Adding timestamp to %s" "$TIMESTAMP_PATH"
    printf '%s%s\n' "$TIMESTAMP_HEADER" "$_timestamp" >> "$TIMESTAMP_PATH"
  fi
}


log_init TIMESTAMP

# Load defaults
[ -n "$TIMESTAMP_DEFAULTS" ] && read_envfile "$TIMESTAMP_DEFAULTS" NOTIFY


# Pick up the path to the timestamp file from the command line, if empty.
if [ -z "$TIMESTAMP_PATH" ]; then
  if [ $# -gt 0 ]; then
    TIMESTAMP_PATH="$1"
    shift
  else
    error "No path to timestamp given"
  fi
fi

# Timestamp once or continuously, depending on the value of TIMESTAMP_SLEEP.
if [ -z "$TIMESTAMP_SLEEP" ] || [ "$TIMESTAMP_SLEEP" -le 0 ]; then
  timestamp_set
else
  while true; do
    timestamp_set
    sleep "$TIMESTAMP_SLEEP"
  done
fi
