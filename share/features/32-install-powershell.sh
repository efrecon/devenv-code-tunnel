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

# Version of Powershell to install. Empty to disable.
: "${INSTALL_POWERSHELL_VERSION:="7.5.0"}"

# Prefix where to install Node.js. We have a default here, but the main prefix
# comes from the calling install.sh.
: "${INSTALL_PREFIX:="/usr/local"}"

# Root URL where to find the tarballs.
: "${INSTALL_ROOTURL:="https://github.com/PowerShell/PowerShell/releases/download"}"

log_init INSTALL


if ! check_command "pwsh" && [ -n "$INSTALL_POWERSHELL_VERSION" ]; then
  # Install dependencies as per
  # https://learn.microsoft.com/en-us/powershell/scripting/install/install-alpine?view=powershell-7.5#installation-steps
  install_packages \
    ca-certificates \
    less \
    ncurses-terminfo-base \
    krb5-libs \
    libgcc \
    libintl \
    libssl3 \
    libstdc++ \
    tzdata \
    userspace-rcu \
    zlib \
    icu-libs \
    curl
  install_packages \
    --repository https://dl-cdn.alpinelinux.org/alpine/edge/main \
    --no-cache \
    lttng-ust \
    openssh-client

  # Find out the OS, add the musl suffix if needed.
  os=$(uname | to_lower)
  if is_musl_os; then
    os="${os}-musl"
  fi

  # Convert the local architecture to the one used by powershell.
  arch=$(uname -m)
  [ "$arch" = "x86_64" ] && arch="x64"
  [ "$arch" = "x686" ] && arch="x86"
  [ "$arch" = "aarch64" ] && arch="arm64"

  # Download and install
  INSTALL_TGZURL="${INSTALL_ROOTURL}/v${INSTALL_POWERSHELL_VERSION}/powershell-${INSTALL_POWERSHELL_VERSION}-${os}-${arch}.tar.gz"
  verbose "Installing powershell from %s" "$INSTALL_TGZURL"
  as_root mkdir -p "${INSTALL_PREFIX}/share/powershell"
  download "${INSTALL_TGZURL}" |
    as_root tar -C "${INSTALL_PREFIX}/share/powershell" -xzf -
  as_root chmod a+x "${INSTALL_PREFIX}/share/powershell/pwsh"
  as_root ln -sf "${INSTALL_PREFIX}/share/powershell/pwsh" "${INSTALL_PREFIX}/bin/pwsh"

  verbose "Installed powershell %s inside %s. Running version: %s" \
    "$INSTALL_POWERSHELL_VERSION" \
    "${INSTALL_PREFIX}/share/powershell" \
    "$("${INSTALL_PREFIX}/bin/pwsh" --version)"
fi
