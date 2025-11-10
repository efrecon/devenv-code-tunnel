#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common system install; do
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

: "${INSTALL_DOCKER_URL:="https://get.docker.com"}"
: "${INSTALL_DOCKER_SHA512:="48ab5cdde63b4f55a12b935c3131167ba2b68bcadb8dc68452142e4c30070cd6be89556efdf0ce8f15bedf9d828f880ac1943384cbbdb2e7746100695c25b53c"}"

log_init INSTALL


verbose "installing docker"
if ! command_present "docker"; then
  if is_os_family alpine; then
    install_packages docker docker-cli-buildx docker-cli-compose fuse-overlayfs
  else
    as_root internet_script_installer "$INSTALL_DOCKER_URL" docker "$INSTALL_DOCKER_SHA512"
  fi
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
  if is_os_family alpine; then
    as_root addgroup "$USR" "docker"
  else
    groupmod -aU "$USR" docker || warn "Cannot add user $USR to docker group"
  fi
else
  warn "No user specified, docker will not be configured"
fi
