#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
NOTIFY_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common system; do
  for d in ../../lib ../lib lib; do
    if [ -d "${NOTIFY_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${NOTIFY_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done


# All following vars have defaults here, but will be set and inherited from
# the calling tunnel.sh script.
: "${NOTIFY_VERBOSE:="${TUNNEL_VERBOSE:-"0"}"}"
: "${NOTIFY_LOG:="${TUNNEL_LOG:-"2"}"}"

: "${NOTIFY_PATH:=""}"
: "${NOTIFY_SLEEP:="1"}"

# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="Trigger commands on changes"
while getopts "f:s:vh-" opt; do
  case "$opt" in
    f) # File to watch
      NOTIFY_PATH="$OPTARG";;
    s) # Sleep time between checks
      NOTIFY_SLEEP="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      NOTIFY_VERBOSE=$((NOTIFY_VERBOSE + 1));;
    h) # Show help
      usage 0 NOTIFY
      ;;
    -) # End of options, file name to follow
      break;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done
shift $((OPTIND - 1))

log_init NOTIFY

if [ -z "$NOTIFY_PATH" ]; then
  error "No path to watch given"
fi

LAST_WRITE=
while true; do
  if [ -f "$NOTIFY_PATH" ]; then
    write="$(stat -c "%Y" "$NOTIFY_PATH")"
    if [ -z "$LAST_WRITE" ]; then
      LAST_WRITE="$write"
    elif [ "$LAST_WRITE" -lt 0 ]; then
      LAST_WRITE="$write"
      verbose "File %s created, running command" "$NOTIFY_PATH"
      "$@"
    elif [ "$write" != "$LAST_WRITE" ]; then
      LAST_WRITE="$write"
      verbose "File %s changed, running command" "$NOTIFY_PATH"
      "$@"
    else
      trace "File %s not changed" "$NOTIFY_PATH"
    fi
  else
    trace "File %s not found" "$NOTIFY_PATH"
    LAST_WRITE=-1
  fi
  sleep "$NOTIFY_SLEEP"
done
