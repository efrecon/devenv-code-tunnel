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

# All following vars have defaults here, but will be set and inherited from
# calling install.sh script in the normal case.
: "${INSTALL_VERBOSE:=0}"
: "${INSTALL_LOG:=2}"
: "${INSTALL_USER:="coder"}"

: "${INSTALL_PODMAN_UIDS:="5000"}"
: "${INSTALL_PODMAN_GIDS:="$INSTALL_PODMAN_UIDS"}"

log_init INSTALL


verbose "installing podman"
if ! check_command "podman"; then
  install_packages podman passt fuse-overlayfs
fi

USR=$(printf %s\\n "$INSTALL_USER" | cut -d: -f1)
printf "%s:10000:%d" "$USR" "$INSTALL_PODMAN_UIDS" > /etc/subuid
printf "%s:10000:%d" "$USR" "$INSTALL_PODMAN_GIDS" > /etc/subgid
