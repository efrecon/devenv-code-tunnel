#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
CRON_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common delegate system; do
  for d in ../../lib ../lib lib; do
    if [ -d "${CRON_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${CRON_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Arrange to set the CODER_BIN variable to the name of the script
bin_name


# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at CRON_LOG.
: "${CRON_VERBOSE:="${TUNNEL_VERBOSE:-"0"}"}"

# Where to send logs
: "${CRON_LOG:="${TUNNEL_LOG:-"2"}"}"

# Prefix where things are installed.
: "${CRON_PREFIX:="${TUNNEL_PREFIX:-"/usr/local"}"}"

# How often should we check for action
: "${CRON_INTERVAL:=60}"

# Format of the date to use when checking for action
: "${CRON_DATE_FORMAT:=%Y-%m-%d %H:%M:%S}"

# Regular expression to match the date format to decide when to run. Empty
# (default) for never.
: "${CRON_WHEN:=""}"

# Environment file to load for reading defaults from.
: "${CRON_DEFAULTS:="${CRON_ROOTDIR}/../${CODER_BIN}.env"}"

# Binary to run, will be prepended to the arguments given to this script. Empty
# by default.
: "${CRON_BIN:=""}"

# Detach in the background (but the default will be to daemonize via env file)
: "${CRON_DAEMONIZE:=0}"

# Prevent detaching in the background (RESERVED for use by ourselves)
: "${_CRON_PREVENT_DAEMONIZATION:=0}"


# shellcheck disable=SC2034 # Used from functions in common.sh
CODE_DESCR="Simplistic cron daemon startup"
while getopts "b:w:vh-" opt; do
  case "$opt" in
    b) # Binary to run, will be prepended to the arguments given to this script.
      CRON_BIN="$OPTARG";;
    w) # When to run the cron job. Empty (default) for never.
      CRON_WHEN="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      CRON_VERBOSE=$((CRON_VERBOSE + 1));;
    h) # Show help
      usage 0 CRON;;
    -) # End of options, everything else passed to binary blindly, or forms command to run.
      break;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done
shift $((OPTIND - 1))

log_init CRON

# Load defaults
[ -n "$CRON_DEFAULTS" ] && read_envfile "$CRON_DEFAULTS" CRON

# When no command is provided, bail out
if [ -z "$CRON_BIN" ] && [ $# -eq 0 ]; then
  error "No command to run"
  usage 1
fi
check_int "$CRON_INTERVAL"

# If we are to daemonize, do it now and exit. Export all our variables to the
# daemon so it starts the same way this script was started.
if ! is_true "$_CRON_PREVENT_DAEMONIZATION" && is_true "$CRON_DAEMONIZE"; then
  # Do not daemonize the daemon!
  _CRON_PREVENT_DAEMONIZATION=1
  CRON_DAEMONIZE=0
  daemonize CRON "$@"
fi


verbose "Will run when date matches $CRON_WHEN (interval: ${CRON_INTERVAL}s, PID: $$): $CRON_BIN $*"
while true; do
  now=$(date +"$CRON_DATE_FORMAT")
  if [ -n "$CRON_WHEN" ] && printf %s\\n "$now" | grep -qE "$CRON_WHEN"; then
    verbose "Running at $now"
    if [ -z "$CRON_BIN" ]; then
      if "$@"; then
        debug "Command ran successfully"
      else
        warn "Command failed"
      fi
    elif "$CRON_BIN" "$@"; then
      debug "Command ran successfully"
    else
      warn "Command failed"
    fi
  else
    trace "$now does not match $CRON_WHEN"
  fi
  sleep "$CRON_INTERVAL"
done
