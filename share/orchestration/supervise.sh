#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Absolute location of the script where this script is located.
SUPERVISE_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common system delegate; do
  for d in ../../lib ../lib lib; do
    if [ -d "${SUPERVISE_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${SUPERVISE_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Arrange to set the CODER_BIN variable to the name of the script
bin_name


# All following vars have defaults here, but will be set and inherited from
# the calling tunnel.sh script.
: "${SUPERVISE_VERBOSE:="${TUNNEL_VERBOSE:-"0"}"}"
: "${SUPERVISE_LOG:="${TUNNEL_LOG:-"2"}"}"

# Executable to supervise.
: "${SUPERVISE_BINPATH:=""}"

# Its name, for logging purposes. Defaults to the basename of the executable.
: "${SUPERVISE_NAME:="$(basename "$SUPERVISE_BINPATH")"}"

# Maximum delay between restarts, in seconds. Defaults to 120.
: "${SUPERVISE_MAXDELAY:="120"}"

# Environment file to load for reading defaults from.
: "${SUPERVISE_DEFAULTS:="${SUPERVISE_ROOTDIR}/../../etc/${CODER_BIN}.env"}"


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="Supervise a script and restart on errors"
while getopts "b:n:vh-" opt; do
  case "$opt" in
    b) # Specify the executable to supervise
      SUPERVISE_BINPATH=$OPTARG;;
    n) # Specify the name for logging purposes
      SUPERVISE_NAME=$OPTARG;;
    v) # Increase verbosity, repeat to increase
      SUPERVISE_VERBOSE=$((SUPERVISE_VERBOSE + 1));;
    h) # Show help
      usage 0 SUPERVISE
      ;;
    -) # End of options, file name to follow
      break;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done
shift $((OPTIND - 1))


log_init SUPERVISE

# Load defaults
[ -n "$SUPERVISE_DEFAULTS" ] && read_envfile "$SUPERVISE_DEFAULTS" SUPERVISE

[ -z "$SUPERVISE_BINPATH" ] && error "No executable specified to supervise. Use -b option or set SUPERVISE_BINPATH in the environment."

_sup_running=1
_delay=0

while [ "$_sup_running" = "1" ]; do
  info "Starting %s at %s in the background" "$SUPERVISE_NAME" "$SUPERVISE_BINPATH"
  spawn "$SUPERVISE_BINPATH" "$@" > /dev/null
  _rc=0
  spawn_wait || _rc=$?
  [ "$_sup_running" = "0" ] && break
  [ "$_rc" -eq 0 ] && break
  debug "%s exited with %d, restarting in %d seconds" "$SUPERVISE_NAME" "$_rc" "$_delay"
  [ "$_delay" -gt 0 ] && sleep "$_delay" || true
  if [ "$_delay" -eq 0 ]; then
    _delay=1
  elif [ "$((_delay * 2))" -gt "$SUPERVISE_MAXDELAY" ]; then
    _delay="$SUPERVISE_MAXDELAY"
  else
    _delay=$((_delay * 2))
  fi
done
