#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
ENTRYPOINT_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )


if "${ENTRYPOINT_ROOTDIR}/services.sh"; then
  exec "${ENTRYPOINT_ROOTDIR}/tunnel.sh" "$@"
fi
