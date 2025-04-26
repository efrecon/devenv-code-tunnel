#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
TUNNEL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common system; do
  for d in ../lib lib; do
    if [ -d "${TUNNEL_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${TUNNEL_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
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

# Name of the tunnel, when empty the hostname will be used if it was set to
# something sensible, i.e. not the shortname of the container ID. Each time the
# name changes, you will have to reauthorize the tunnel with -f
: "${TUNNEL_NAME:=""}"

# Hook to run before starting the tunnel. This is useful for setting up
# environment variables or running commands that need to be run before the
# tunnel starts. The hook is run as the tunnel user.
: "${TUNNEL_HOOK:=""}"

# Force reauthorization of the device
: "${TUNNEL_FORCE:="0"}"

# Prefixes where things are installed.
: "${TUNNEL_PREFIX:="/usr/local"}"
: "${TUNNEL_USER_PREFIX:="${HOME}/.local"}"

# Alias for the home user
: "${TUNNEL_ALIAS:=}"

# Port of the SSH daemon to tunnel via cloudflare
: "${TUNNEL_SSH:="2222"}"

# Github user to fetch keys from
: "${TUNNEL_GITHUB_USER:=""}"


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="tunnel starter"
while getopts "a:fg:k:l:n:p:s:vh" opt; do
  case "$opt" in
    a) # Alias for the home user
      TUNNEL_ALIAS="$OPTARG";;
    f) # Force device authorization again
      TUNNEL_FORCE="1";;
    g) # GitHub user to fetch keys from and restrict ssh access to
      TUNNEL_GITHUB_USER="$OPTARG";;
    k) # Internet hook to run before starting the tunnel
      TUNNEL_HOOK="$OPTARG";;
    l) # Where to send logs
      TUNNEL_LOG="$OPTARG";;
    n) # Name of the tunnel, empty for random name
      TUNNEL_NAME="$OPTARG";;
    p) # Tunnel provider
      TUNNEL_PROVIDER="$OPTARG";;
    s) # Port of the SSH daemon, to tunnel via cloudflare
      TUNNEL_SSH="$OPTARG";;
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

# Arrange for a link to exists, pointing to the real home of the user. Make this
# the new home as much as possible.
alias_create() {
  AHOME=$(dirname "$HOME")/$1
  if ! [ -d "$AHOME" ]; then
    as_root ln -sf "$HOME" "$AHOME"
    as_root sed -ibak -E -e "s|${HOME}|${AHOME}|g" "/etc/passwd"
    TUNNEL_USER_PREFIX=$(printf %s\\n "$TUNNEL_USER_PREFIX" | sed -E "s|${HOME}|${AHOME}|g")
    HOME=$AHOME
    export HOME
  fi
}


# Create the alias for the home user
[ -n "$TUNNEL_ALIAS" ] && alias_create "$TUNNEL_ALIAS"

# shellcheck disable=SC2034 # Used in tunnel implementations
TUNNEL_ORIGINAL_NAME=$TUNNEL_NAME

TUNNEL_BINS_DIR=${TUNNEL_ROOTDIR%/}/../share/tunnel
if ! [ -d "$TUNNEL_BINS_DIR" ]; then
  error "No tunnel binaries found in %s" "$TUNNEL_BINS_DIR"
fi

# Pick a name, from hostname or at random
if [ -z "$TUNNEL_NAME" ]; then
  # If the hostname is not a random name, use it as the tunnel name.
  if ! hostname | grep -qE '[a-f0-9]{12}'; then
    TUNNEL_NAME=$(hostname)
  else
    TUNNEL_NAME=$(generate_random)
  fi
elif [ "$TUNNEL_NAME" = "-" ]; then
  TUNNEL_NAME=
fi

# Start services
export_varset "TUNNEL"
if [ -x "${TUNNEL_BINS_DIR}/services.sh" ]; then
  info "Starting services"
  SERVICES_LOG=$TUNNEL_LOG \
  SERVICES_VERBOSE=$TUNNEL_VERBOSE \
  SERVICES_PREFIX=$TUNNEL_PREFIX \
    "${TUNNEL_BINS_DIR}/services.sh"
fi

# Start the Internet hook to perform extra setup
if [ -n "$TUNNEL_HOOK" ]; then
  info "Running hook: %s" "$TUNNEL_HOOK"
  internet_installer "$TUNNEL_HOOK" hook ""
fi

# Start tunnels in the background
for tunnel in codecli cloudflare; do
  if [ -x "${TUNNEL_BINS_DIR}/${tunnel}.sh" ]; then
    # TODO: Log the output of the tunnel helpers to files?
    info "Starting %s tunnel" "$tunnel"
    # shellcheck disable=SC1090
    "${TUNNEL_BINS_DIR}/${tunnel}.sh" &
  fi
done

# TODO: Rotate the logs from tunnels and services at regular intervals
# TODO: Make re-expose of logs a configurable option?

while true; do
  sleep 1
done