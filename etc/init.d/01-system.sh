#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
SYSTEM_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common system; do
  for d in ../../lib ../lib lib; do
    if [ -d "${SYSTEM_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${SYSTEM_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Arrange to set the CODER_BIN variable to the name of the script
bin_name



# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at SYSTEM_LOG.
: "${SYSTEM_VERBOSE:=0}"

# Where to send logs
: "${SYSTEM_LOG:=2}"

# inotify settings (maximum for vscode)
: "${SYSTEM_INOTIFY_MAX:=524288}"

# Environment file to load for reading defaults from.
: "${SYSTEM_DEFAULTS:="${SYSTEM_ROOTDIR}/../${CODER_BIN}.env"}"


# shellcheck disable=SC2034 # Used from functions in common.sh
CODE_DESCR="System tweaking"
while getopts "l:vh" opt; do
  case "$opt" in
    l) # Where to send logs
      SYSTEM_LOG="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      SYSTEM_VERBOSE=$((SYSTEM_VERBOSE + 1));;
    h) # Show help
      usage 0 SYSTEM
      ;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done

log_init SYSTEM

# Load defaults
[ -n "$SYSTEM_DEFAULTS" ] && read_envfile "$SYSTEM_DEFAULTS" SYSTEM

current=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || true)
if [ "$current" != "$SYSTEM_INOTIFY_MAX" ]; then
  verbose "Trying to set inotify max_user_watches to %s" "$SYSTEM_INOTIFY_MAX"
  as_root sysctl -w fs.inotify.max_user_watches="$SYSTEM_INOTIFY_MAX" || true
fi
