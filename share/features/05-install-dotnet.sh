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

# Version of .NET to install. Empty to disable. STS, LTS, 2-hand, 3-hand
# versions
: "${INSTALL_DOTNET_CHANNEL:="8.0"}"

# Quality for the current channel.
: "${INSTALL_DOTNET_QUALITY:="GA"}"

# Prefix where to install Node.js. We have a default here, but the main prefix
# comes from the calling install.sh.
: "${INSTALL_PREFIX:="/usr/local"}"

# Location of the install script.
: "${INSTALL_URL:="https://dot.net/v1/dotnet-install.sh"}"

# sha512 checksum of the install script.
: "${INSTALL_SHA512:="749691260ef298c4c1adb6f4e78e47dff1963d57e8d2490bcfb105bad2f6a687093bf0057de5296e6a212dc40bdbbdaffbcd995f9746c8805c4e0024fdbed014"}"

log_init INSTALL


if ! check_command "dotnet" && [ -n "$INSTALL_DOTNET_CHANNEL" ]; then
  # Install dependencies as per
  # https://learn.microsoft.com/en-us/dotnet/core/install/linux-alpine?tabs=dotnet8#dependencies
  install_packages libgcc libssl3 libstdc++ zlib icu-libs icu-data-full

  INSTALL_DIR="${INSTALL_PREFIX}/share/dotnet"
  as_root mkdir -p "${INSTALL_DIR}"
  as_root internet_install "$INSTALL_URL" dotnet "$INSTALL_SHA512" \
            --channel "$INSTALL_DOTNET_CHANNEL" \
            --quality "$INSTALL_DOTNET_QUALITY" \
            --install-dir "$INSTALL_DIR" \
            --no-path
  as_root ln -sf "${INSTALL_DIR}/dotnet" "${INSTALL_PREFIX}/bin/dotnet"

  verbose "Installed .NET %s %s inside %s. Running version: %s" \
    "$INSTALL_DOTNET_CHANNEL" \
    "$INSTALL_DOTNET_QUALITY" \
    "$INSTALL_DIR" \
    "$("${INSTALL_PREFIX}/bin/dotnet" --version)"
fi
