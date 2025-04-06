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


verbose "Installing sudo"
if ! check_command "sudo"; then
  install_packages sudo
fi

if [ -n "$INSTALL_USER" ]; then
  USR=$(printf %s\\n "$INSTALL_USER" | cut -d: -f1)
  verbose "Ensure $USR can sudo without password"
  printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$USR" > "/etc/sudoers.d/$USR"
else
  warn "No user specified, sudo will not be configured"
fi
