#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common install system; do
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
: "${INSTALL_PREFIX:="/usr/local"}"

# Version of Powershell to install. Empty to disable.
: "${INSTALL_POWERSHELL_VERSION:="7.5.1"}"

# Root URL where to find the tarballs.
: "${INSTALL_POWERSHELL_ROOTURL:="https://github.com/PowerShell/PowerShell/releases/download"}"

# Find out the OS, add the musl suffix if needed.
os=$(get_os)
if is_musl_os; then
  os="${os}-musl"
fi
: "${INSTALL_POWERSHELL_URL:="${INSTALL_POWERSHELL_ROOTURL}/v${INSTALL_POWERSHELL_VERSION}/powershell-${INSTALL_POWERSHELL_VERSION}-${os}-$(get_arch).tar.gz"}"
: "${INSTALL_POWERSHELL_SUMS=${INSTALL_POWERSHELL_ROOTURL}/v${INSTALL_POWERSHELL_VERSION}/hashes.sha256}"


log_init INSTALL


if ! check_command "pwsh" && [ -n "$INSTALL_POWERSHELL_VERSION" ]; then
  if [ "$(get_arch)" = "arm64" ] && is_musl_os; then
    warn "No Powershell for arm64 musl available. Skipping installation."
    return 0
  fi

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

  # Download and install
  internet_tgz_installer \
    "$INSTALL_POWERSHELL_URL" \
    "${INSTALL_PREFIX}/share/powershell" \
    "powershell" \
    "$INSTALL_POWERSHELL_SUMS"
  as_root chmod a+x "${INSTALL_PREFIX}/share/powershell/pwsh"
  as_root ln -sf "${INSTALL_PREFIX}/share/powershell/pwsh" "${INSTALL_PREFIX}/bin/pwsh"

  verbose "Installed powershell %s inside %s. Running version: %s" \
    "$INSTALL_POWERSHELL_VERSION" \
    "${INSTALL_PREFIX}/share/powershell" \
    "$("${INSTALL_PREFIX}/bin/pwsh" --version)"
fi
