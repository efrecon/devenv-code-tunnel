#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

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
: "${INSTALL_PREFIX:="/usr/local"}"
: "${INSTALL_USER_PREFIX:="${HOME}/.local"}"
: "${INSTALL_TARGET:="user"}"

: "${INSTALL_GITHUB_VERSION:="2.71.2"}"
: "${INSTALL_GITHUB_URL:="https://github.com/cli/cli/releases/download/v${INSTALL_GITHUB_VERSION}/gh_${INSTALL_GITHUB_VERSION}_$(get_os)_$(get_arch x86_64 amd64 i686 386).tar.gz"}"
: "${INSTALL_GITHUB_SUMS:="https://github.com/cli/cli/releases/download/v${INSTALL_GITHUB_VERSION}/gh_${INSTALL_GITHUB_VERSION}_checksums.txt"}"

log_init INSTALL


# Install the github CLI in the proper directory location, i.e. as per
# INSTALL_TARGET preference.
[ "$INSTALL_TARGET" = "user" ] \
  && BINDIR="${INSTALL_USER_PREFIX}/bin" \
  || BINDIR="${INSTALL_PREFIX}/bin"
gh=$(internet_bintgz_installer \
          "$INSTALL_GITHUB_URL" \
          "$BINDIR" \
          "gh" \
          "$INSTALL_GITHUB_SUMS")

# Verify installation through printing the version.
verbose "Installed github CLI %s" "$("$gh" --version)"

