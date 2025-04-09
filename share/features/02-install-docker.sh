#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the common library
for d in ../../lib ../lib lib; do
  if [ -d "${INSTALL_ROOTDIR}/$d" ]; then
    # shellcheck disable=SC1091 source=lib/common.sh
    . "${INSTALL_ROOTDIR}/$d/common.sh"
    break
  fi
done

log_init INSTALL


verbose "installing docker"
if ! check_command "docker"; then
  install_packages docker docker-cli-buildx docker-cli-compose fuse-overlayfs
fi

# Create the docker group if it does not exist
if ! getent group "docker" > /dev/null; then
  verbose "Creating docker group"
  as_root addgroup "docker" || warn "Cannot create docker group"
else
  verbose "Docker group already exists"
fi

# Add the user to the docker group
if [ -n "$INSTALL_USER" ]; then
  USR=$(printf %s\\n "$INSTALL_USER" | cut -d: -f1)
  as_root addgroup "$USR" "docker"
else
  warn "No user specified, docker will not be configured"
fi
