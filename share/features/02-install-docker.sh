#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common system; do
  for d in ../../lib ../lib lib; do
    if [ -d "${INSTALL_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${INSTALL_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done


# All following vars have defaults here, but will be set and inherited from
# calling install.sh script in the normal case.
: "${INSTALL_VERBOSE:=0}"
: "${INSTALL_LOG:=2}"
: "${INSTALL_USER:="coder"}"

log_init INSTALL


verbose "installing docker"
if ! command_present "docker"; then
  # TODO: On anything else than alpine, run the CI install script, see: https://github.com/docker/docker-install
  install_packages docker docker-cli-buildx docker-cli-compose fuse-overlayfs
fi

# Create the docker group if it does not exist
if ! getent group "docker" > /dev/null; then
  debug "Creating docker group"
  as_root addgroup "docker" || warn "Cannot create docker group"
else
  trace "Docker group already exists"
fi

# Add the user to the docker group
if [ -n "$INSTALL_USER" ]; then
  USR=$(printf %s\\n "$INSTALL_USER" | cut -d: -f1)
  as_root addgroup "$USR" "docker"
else
  warn "No user specified, docker will not be configured"
fi
