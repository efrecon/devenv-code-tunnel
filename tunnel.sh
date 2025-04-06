#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
TUNNEL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the common library
for d in ../lib lib; do
  if [ -d "${TUNNEL_ROOTDIR}/$d" ]; then
    # shellcheck disable=SC1091 source=lib/common.sh
    . "${TUNNEL_ROOTDIR}/$d/common.sh"
    break
  fi
done

# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at TUNNEL_LOG.
: "${TUNNEL_VERBOSE:=0}"

# Where to send logs
: "${TUNNEL_LOG:=2}"

: "${TUNNEL_STORAGE:="${HOME}/.vscode-tunnel"}"

: "${TUNNEL_PROVIDER:="github"}"

: "${TUNNEL_NAME:="coder"}"

: "${TUNNEL_PREFIX:="/usr/local"}"

: "${TUNNEL_SERVICES:="${TUNNEL_PREFIX}/etc/init.d"}"

CODER_DESCR="tunnelled environment starter"
while getopts "l:n:vh" opt; do
  case "$opt" in
    n) # Name of the tunnel
      TUNNEL_NAME="$OPTARG";;
    l) # Where to send logs
      TUNNEL_LOG="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      TUNNEL_VERBOSE=$((TUNNEL_VERBOSE + 1));;
    h) # Show help
      usage 0 TUNNEL
      ;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done

# Initialize
log_init TUNNEL

VSCODE_CLI_DATA_DIR=$TUNNEL_STORAGE
export VSCODE_CLI_DATA_DIR

is_logged_in() {
  if [ -f "${TUNNEL_STORAGE%/}/token.json" ]; then
    token=$(cat "${TUNNEL_STORAGE%/}/token.json")
    if [ "$token" != "null" ]; then
      return 0
    fi
  fi
  return 1
}

tunnel() {
  if [ -z "$TUNNEL_NAME" ]; then
    code tunnel --accept-server-license-terms --random-name
  else
    code tunnel --accept-server-license-terms --name "$TUNNEL_NAME"
  fi
}

for svc in "${TUNNEL_SERVICES%/}"/*.sh; do
  if [ -f "$svc" ]; then
    if ! [ -x "$svc" ]; then
      verbose "Making $svc executable"
      chmod a+x "$svc"
    fi
    verbose "Starting $svc"
    "$svc"
  fi
done


if is_logged_in; then
  tunnel
else
  code tunnel user login --provider "$TUNNEL_PROVIDER"
  tunnel
fi
