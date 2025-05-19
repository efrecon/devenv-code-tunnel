#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common install system; do
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
: "${INSTALL_PREFIX:="/usr/local"}"
: "${INSTALL_USER_PREFIX:="${HOME}/.local"}"
: "${INSTALL_TARGET:="user"}"

# Build of vscode to install: only stable or insiders are available.
: "${INSTALL_CODE_BUILD:="stable"}"

# URL to download the code CLI from.
: "${INSTALL_CODE_URL:="https://code.visualstudio.com/sha/download?build=${INSTALL_CODE_BUILD}&os=cli-alpine-$(get_arch)"}"

log_init INSTALL


# Install the code CLI in the proper directory location, i.e. as per
# INSTALL_TARGET preference.
debug "Installing code CLI"
[ "$INSTALL_TARGET" = "user" ] \
  && BINDIR="${INSTALL_USER_PREFIX}/bin" \
  || BINDIR="${INSTALL_PREFIX}/bin"
code=$(internet_bintgz_installer \
          "$INSTALL_CODE_URL" \
          "$BINDIR" \
          "code" \
          "" \
          "code*")

# Install the code CLI dependencies.
as_root install_packages "libstdc++"

# Verify dependencies through printing the version.
verbose "Installed code CLI %s" "$("$code" --version)"
