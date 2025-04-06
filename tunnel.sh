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

(
  set -m
  nohup "dockerd" </dev/null >/dev/null 2>&1 &
)

if is_logged_in; then
  tunnel
else
  code tunnel user login --provider "$TUNNEL_PROVIDER"
  tunnel
fi
