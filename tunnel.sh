#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
TUNNEL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common system install; do
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

# Services to start. When empty, all services will be started.
: "${TUNNEL_SERVICES:=""}"

# List of tunnels to establish. When empty, all tunnels will be started.
: "${TUNNEL_TUNNELS:=""}"

# List of services which logs we should re-expose to the main container log.
# When empty, all services will be re-exposed.
: "${TUNNEL_REEXPOSE:="code"}"


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="tunnel starter"
while getopts "a:fg:k:l:L:n:p:s:S:T:vh" opt; do
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
    L) # List of services to re-expose in log
      TUNNEL_REEXPOSE="$OPTARG";;
    n) # Name of the tunnel, empty for random name
      TUNNEL_NAME="$OPTARG";;
    p) # Tunnel provider
      TUNNEL_PROVIDER="$OPTARG";;
    s) # Port of the SSH daemon, to tunnel via cloudflare
      TUNNEL_SSH="$OPTARG";;
    S) # Services to start
      TUNNEL_SERVICES="$OPTARG";;
    T) # Tunnels to start
      TUNNEL_TUNNELS="$OPTARG";;
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


# Find a sub-directory in the hierarchy of the tunnel root directory.
# $1 is the sub-directory to look for
# $2 is the name of the directory to look for, used in error messages
# Returns the full path to the directory if found, otherwise exit with error
# message
pick_dir() {
  [ -z "${1:-}" ] && error "pick_dir: No sub-directory given"
  for d in "${TUNNEL_ROOTDIR%/}/.." "$TUNNEL_ROOTDIR"; do
    if [ -d "${d%/}/$1" ]; then
      printf %s\\n "${d%/}/$1"
      return 0
    fi
  done
  error "No %s binaries found in hierarchy" "${2:-$(basename "$1")}"
}


# Create the alias for the home user
[ -n "$TUNNEL_ALIAS" ] && alias_create "$TUNNEL_ALIAS"

# shellcheck disable=SC2034 # Used in tunnel implementations
TUNNEL_ORIGINAL_NAME=$TUNNEL_NAME

# Make sure we can access scripts that we will make use of.
TUNNEL_TUNNELS_DIR=$(pick_dir "share/tunnels")
TUNNEL_SERVICES_DIR=$(pick_dir "etc/init.d")

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

# Export all variables that start with TUNNEL_ so that they are available to
# subprocesses.
export_varset "TUNNEL"

# Start services from the init.d directory. Services are started in order and in
# the foreground. Some of these will respawn in the background.
start_deps "service" "$TUNNEL_SERVICES_DIR" "$TUNNEL_SERVICES" '??-*.sh' >/dev/null

# Start the Internet hook to perform extra setup
if [ -n "$TUNNEL_HOOK" ]; then
  info "Running hook: %s" "$TUNNEL_HOOK"
  internet_script_installer "$TUNNEL_HOOK" hook ""
fi

# Start tunnels in the background
start_deps "tunnel" "$TUNNEL_TUNNELS_DIR" "$TUNNEL_TUNNELS" "*.sh" 1 >/dev/null

# TODO: Rotate the logs from tunnels and services at regular intervals

while true; do
  sleep 1
done