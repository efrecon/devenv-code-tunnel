#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Absolute location of the script where this script is located.
CLEAR_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common; do
  for d in ../../lib ../lib lib; do
    if [ -d "${CLEAR_ROOTDIR}/$d" ] && [ -f "${CLEAR_ROOTDIR}/$d/${lib}.sh" ]; then
      # shellcheck disable=SC1090
      . "${CLEAR_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Arrange to set the CODER_BIN variable to the name of the script
bin_name


# All following vars have defaults here, but will be set and inherited from
# the calling tunnel.sh script. They are read before the variables are cleared.
: "${CLEAR_VERBOSE:="${TUNNEL_VERBOSE:-"0"}"}"
: "${CLEAR_LOG:="${TUNNEL_LOG:-"2"}"}"
# Space-separated list of prefixes: all variables named <prefix>_* are removed
# from the environment of the command. Options -p replace this list.
: "${CLEAR_PREFIXES:="TUNNEL"}"
# Environment file to load for reading defaults from.
: "${CLEAR_DEFAULTS:="${CLEAR_ROOTDIR}/../../etc/${CODER_BIN}.env"}"


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="Run a command without some environment variables"
_prefixes=
while getopts "p:vh-" opt; do
  case "$opt" in
    p) # Prefix of variables to remove, repeat for several. Default: TUNNEL
      _prefixes="${_prefixes:+"$_prefixes "}$OPTARG";;
    v) # Increase verbosity, repeat to increase
      CLEAR_VERBOSE=$((CLEAR_VERBOSE + 1));;
    h) # Show help
      usage 0 CLEAR
      ;;
    -) # End of options, command to run follows
      break;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done
shift $((OPTIND - 1))
[ -n "$_prefixes" ] && CLEAR_PREFIXES=$_prefixes

log_init CLEAR

# Load defaults
[ -n "$CLEAR_DEFAULTS" ] && read_envfile "$CLEAR_DEFAULTS" CLEAR

[ -z "${1:-}" ] && error "No command to run given"

for _prefix in $CLEAR_PREFIXES; do
  case "$_prefix" in
    "" | [0-9]* | *[!A-Za-z0-9_]*) error "Invalid variable prefix: %s" "$_prefix";;
  esac
  debug "Removing %s_* variables from the environment of %s" "$_prefix" "$1"
  unset_varset "$_prefix"
done

# Replace this process, so the command keeps its PID, receives signals directly
# and its exit code is returned as is.
exec "$@"
