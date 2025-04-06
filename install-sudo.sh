#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the common library
for d in ../lib lib; do
  if [ -d "${INSTALL_ROOTDIR}/$d" ]; then
    # shellcheck disable=SC1091 source=lib/common.sh
    . "${INSTALL_ROOTDIR}/$d/common.sh"
    break
  fi
done

# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at INSTALL_LOG.
: "${INSTALL_VERBOSE:=0}"

# Where to send logs
: "${INSTALL_LOG:=2}"

CODER_DESCR="sudo installer"

# Initialize
log_init INSTALL



verbose "Installing sudo"
if ! check_command "sudo"; then
  install_packages sudo
fi
verbose "Ensure $INSTALL_USER can sudo without password"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$INSTALL_USER" > "/etc/sudoers.d/$INSTALL_USER"

