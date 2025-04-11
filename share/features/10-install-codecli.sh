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

# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at INSTALL_LOG.
: "${INSTALL_VERBOSE:=0}"

# Where to send logs
: "${INSTALL_LOG:=2}"

# Prefix where to install the code CLI. We have a default here, but the main
# prefix comes from the calling install.sh.
: "${INSTALL_PREFIX:="/usr/local"}"

# Build of vscode to install: only stable or insiders are available.
: "${INSTALL_CODE_BUILD:="stable"}"

# URL to download the code CLI from.
: "${INSTALL_CODE_URL:="https://code.visualstudio.com/sha/download?build=${INSTALL_CODE_BUILD}&os=cli-alpine-x64"}"

log_init INSTALL


verbose "Installing code CLI"

# Download into a temporary directory and extract the code CLI
tmp=$(mktemp -d)
download "$INSTALL_CODE_URL" - | tar -C "$tmp" -zxf -

# Find the code CLI and move it to the bin directory. This ensures that the
# destination is called "code", but it will find the binary even when it is
# called code-insiders.
find "$tmp" -name 'code*' -exec mv -f \{\} "${INSTALL_PREFIX}/bin/code" \;

# Cleanup the temporary directory
rm -rf "$tmp"

# Install the code CLI dependencies.
as_root install_packages "libstdc++"
