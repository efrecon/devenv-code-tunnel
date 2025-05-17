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
: "${NOTIFY_RESPITE:="2"}"

# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="Trigger commands on changes"
while getopts "f:s:r:vh-" opt; do
  case "$opt" in
    f) # File to watch
      NOTIFY_PATH="$OPTARG";;
    s) # Sleep time between checks
      NOTIFY_SLEEP="$OPTARG";;
    r) # Respite time before running the command.
      NOTIFY_RESPITE="$OPTARG";;
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
check_int "$NOTIFY_SLEEP" "$NOTIFY_RESPITE"


# ```
notify_trigger() {
  if [ "$NOTIFY_RESPITE" -gt 0 ]; then
    debug "File %s changed, available at NOTIFY_CHANGE, running command in %d s" "$1" "$NOTIFY_RESPITE"
  else
    debug "File %s changed, available at NOTIFY_CHANGE, running command" "$1"
  fi

  # Export the path to the file that changed, so that it can be used in the
  # command that is run.
  NOTIFY_CHANGE=$1
  export NOTIFY_CHANGE
  shift 1

  # Run now, or wait for a respite time before running the command. When
  # waiting, schedule in background so each new scheduled command can cancel the
  # previous one.
  if [ "$NOTIFY_RESPITE" -gt 0 ]; then
    # Kill any existing scheduled command
    if [ -n "${NOTIFY_PID:-}" ] && kill -0 "$NOTIFY_PID"; then
      kill -TERM "$NOTIFY_PID" 2>/dev/null || true
    fi
    # Schedule the command to run after the respite time in background
    sleep "$NOTIFY_RESPITE" && "$@" &
    NOTIFY_PID=$!
  else
    "$@"
  fi
}


# ```
notify_poll() {
  LAST_WRITE=
  while true; do
    if [ -f "$NOTIFY_PATH" ]; then
      write="$(stat -c "%Y" "$NOTIFY_PATH")"
      if [ -z "$LAST_WRITE" ]; then
        LAST_WRITE="$write"
      elif [ "$LAST_WRITE" -lt 0 ]; then
        LAST_WRITE="$write"
        notify_trigger "$NOTIFY_PATH" "$@"
      elif [ "$write" != "$LAST_WRITE" ]; then
        LAST_WRITE="$write"
        notify_trigger "$NOTIFY_PATH" "$@"
      else
        trace "File %s not changed" "$NOTIFY_PATH"
      fi
    else
      trace "File %s not found" "$NOTIFY_PATH"
      LAST_WRITE=-1
    fi
    sleep "$NOTIFY_SLEEP"
  done
}


# Monitors a file or directory for changes using inotifywait and triggers a command on relevant events.
#
# Watches the specified path for file modifications or deletions. If monitoring a directory, triggers the command for any file within the directory that is deleted or closed after writing. If monitoring a single file, triggers the command only when that file is closed after writing. The changed file path is passed to the triggered command.
#
# Globals:
#
# * NOTIFY_PATH: Path to the file or directory to watch.
# * NOTIFY_DIR: Directory being watched (set within the function).
#
# Arguments:
#
# * Additional arguments are passed to the triggered command.
#
# Example:
#
# ```bash
# notify_inotify echo "File changed: \$NOTIFY_CHANGE"
# ```
notify_inotify() {
  new_line=$(printf \\n)

  if [ -d "$NOTIFY_PATH" ]; then
    verbose "Watching directory %s with inotifywait" "$NOTIFY_PATH"
    # If the path is a directory, watch for changes in the directory
    NOTIFY_DIR="${NOTIFY_PATH%/}/"
    inotifywait -qmr --format '%w%f' -e delete,close_write "$NOTIFY_DIR" |
    while IFS="$new_line" read -r p; do
      notify_trigger "$p" "$@"
    done
  else
    verbose "Watching file path %s with inotifywait" "$NOTIFY_PATH"
    NOTIFY_DIR="$(dirname "$NOTIFY_PATH")"
    inotifywait -qm --format '%w%f' -e close_write "$NOTIFY_DIR" |
    while IFS="$new_line" read -r p; do
      if [ "$p" = "$NOTIFY_PATH" ]; then
        notify_trigger "$p" "$@"
      fi
    done
  fi
}


if check_command inotifywait; then
  notify_inotify "$@"
else
  notify_poll "$@"
fi
