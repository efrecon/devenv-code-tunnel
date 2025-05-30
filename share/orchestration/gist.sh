#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
GIST_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common system; do
  for d in ../../lib ../lib lib; do
    if [ -d "${GIST_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${GIST_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done


# All following vars have defaults here, but will be set and inherited from
# the calling tunnel.sh script.
: "${GIST_VERBOSE:="${TUNNEL_VERBOSE:-"0"}"}"
: "${GIST_LOG:="${TUNNEL_LOG:-"2"}"}"

# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="gist updater"
while getopts "vh-" opt; do
  case "$opt" in
    v) # Increase verbosity, repeat to increase
      GIST_VERBOSE=$((GIST_VERBOSE + 1));;
    h) # Show help
      usage 0 GIST
      ;;
    -) # End of options, file name to follow
      break;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done
shift $((OPTIND - 1))


log_init GIST

check_command git || exit 1

LWRAP="$GIST_ROOTDIR/lwrap.sh"

for file in "$@"; do
  if [ -f "$file" ]; then
    (
      cd "$(dirname "$file")" || error "Failed to change directory to $(dirname "$file")"
      verbose "Pushing changes to %s to git repository" "$file"
      "$LWRAP" git pull
      "$LWRAP" git add "$(basename "$file")"
      if git status --porcelain | grep -qF "$(basename "$file")"; then
        debug "Changes detected in %s" "$file"
        "$LWRAP" git commit -m "Update tunnel details at $(date)"
        "$LWRAP" git push
      else
        debug "No changes detected in %s" "$file"
      fi
    )
  fi
done
