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
: "${INSTALL_USER:="coder"}"
: "${INSTALL_PREFIX:="/usr/local"}"
: "${INSTALL_USER_PREFIX:="${HOME}/.local"}"
: "${INSTALL_TARGET:="user"}"

: "${INSTALL_CHISEL_VERSION:="1.11.8"}"
: "${INSTALL_CROC_VERSION:="11.1.0"}"

# URL to download chisel and croc from.
: "${INSTALL_CHISEL_URL:="https://github.com/jpillora/chisel/releases/download/v${INSTALL_CHISEL_VERSION}/chisel_${INSTALL_CHISEL_VERSION}_$(get_os)_$(get_golang_arch).gz"}"
: "${INSTALL_CHISEL_SUMS:="https://github.com/jpillora/chisel/releases/download/v${INSTALL_CHISEL_VERSION}/chisel_${INSTALL_CHISEL_VERSION}_checksums.txt"}"

# https://github.com/schollz/croc/releases/download/v11.1.0/croc_v11.1.0_Linux-64bit.tar.gz
: "${INSTALL_CROC_URL:="https://github.com/schollz/croc/releases/download/v${INSTALL_CROC_VERSION}/croc_v${INSTALL_CROC_VERSION}_$(uname -s)-$(get_arch x86_64 64bit i686 32bit aarch64 ARM64).tar.gz"}"
: "${INSTALL_CROC_SUMS:="https://github.com/schollz/croc/releases/download/v${INSTALL_CROC_VERSION}/croc_v${INSTALL_CROC_VERSION}_checksums.txt"}"


log_init INSTALL

[ "$INSTALL_TARGET" = "user" ] \
  && BINDIR="${INSTALL_USER_PREFIX}/bin" \
  || BINDIR="${INSTALL_PREFIX}/bin"

debug "Installing chisel v%s" "$INSTALL_CHISEL_VERSION"

# Install the chisel CLI in the proper directory location, i.e. as per
# INSTALL_TARGET preference.
chisel=$(internet_bin_installer \
                "$INSTALL_CHISEL_URL" \
                "$BINDIR" \
                "chisel" \
                "$INSTALL_CHISEL_SUMS")
verbose "Installed chisel version %s" "$("$chisel" --version)"

# Same for croc.
croc=$(internet_bintgz_installer \
                "$INSTALL_CROC_URL" \
                "$BINDIR" \
                "croc" \
                "$INSTALL_CROC_SUMS")
verbose "Installed %s" "$("$croc" --version)"
