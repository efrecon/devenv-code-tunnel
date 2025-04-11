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

# Where to store tunnel data
: "${TUNNEL_STORAGE:="${HOME}/.vscode-tunnel"}"

# Default tunnel provider
: "${TUNNEL_PROVIDER:="github"}"

# Name of the tunnel, when empty a random name is generated. Each time the
# random name changes, you will have to reauthorize the tunnel with -f
: "${TUNNEL_NAME:=""}"

# Hook to run before starting the tunnel. This is useful for setting up
# environment variables or running commands that need to be run before the
# tunnel starts. The hook is run as the tunnel user.
: "${TUNNEL_HOOK:=""}"

: "${TUNNEL_FORCE:="0"}"

# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="tunnel starter"
while getopts "fk:l:n:p:vh" opt; do
  case "$opt" in
    f) # Force device authorization again
      TUNNEL_FORCE="1";;
    k) # Internet hook to run before starting the tunnel
      TUNNEL_HOOK="$OPTARG";;
    l) # Where to send logs
      TUNNEL_LOG="$OPTARG";;
    n) # Name of the tunnel, empty for random name
      TUNNEL_NAME="$OPTARG";;
    p) # Tunnel provider
      TUNNEL_PROVIDER="$OPTARG";;
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


# Check if the tunnel provider is set and valid.
if [ -z "$TUNNEL_PROVIDER" ]; then
  error "No tunnel provider specified. Please set TUNNEL_PROVIDER to github or azure."
fi
if [ "$TUNNEL_PROVIDER" != "github" ] && [ "$TUNNEL_PROVIDER" != "azure" ]; then
  error "Invalid tunnel provider specified. Please set TUNNEL_PROVIDER to github or azure."
fi

# Generate a name
if [ -z "$TUNNEL_NAME" ]; then
  TUNNEL_NAME=$(generate_random)
elif [ "$TUNNEL_NAME" = "-" ]; then
  TUNNEL_NAME=
fi

# If the hostname is generated, override it with the tunnel name
if hostname | grep -qE '[a-f0-9]{12}'; then
  verbose "Overriding hostname with tunnel name: %s" "$TUNNEL_NAME"
  as_root hostname "$TUNNEL_NAME"
fi

if [ -n "$TUNNEL_HOOK" ]; then
  verbose "Running hook: %s" "$TUNNEL_HOOK"
  internet_install "$TUNNEL_HOOK" hook ""
fi

# Authorize device. This will print out a URL to the console. Open it in a
# browser and authorize the device.
if is_true "$TUNNEL_FORCE"; then
  code tunnel user login --provider "$TUNNEL_PROVIDER"
elif ! is_logged_in; then
  code tunnel user login --provider "$TUNNEL_PROVIDER"
fi

# Start the tunnel
if [ -z "$TUNNEL_NAME" ]; then
  code tunnel --accept-server-license-terms --random-name
else
  code tunnel --accept-server-license-terms --name "$TUNNEL_NAME"
fi
