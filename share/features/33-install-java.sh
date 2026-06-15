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

# Version of Java to install.
: "${INSTALL_JAVA_VERSION:="25.0.3+9"}"
# Main (major) version of Java, i.e. everything before the first dot.
INSTALL_JAVA_MAIN_VERSION="${INSTALL_JAVA_VERSION%%.*}"


# Root URL where to find the tarballs.
: "${INSTALL_JAVA_ROOTURL:="https://github.com/adoptium/temurin${INSTALL_JAVA_MAIN_VERSION}-binaries/releases/download"}"

# Find out the OS, add the alpine prefix if needed, generate the default URLs
os=$(get_os)
arch=$(get_arch aarch64 aarch64)
if is_musl_os; then
  os="alpine-${os}"
fi
file_version=$(printf '%s' "$INSTALL_JAVA_VERSION" | sed 's/[^A-Za-z0-9.-]/_/g')
url_version=$(url_encode "$INSTALL_JAVA_VERSION")
: "${INSTALL_JAVA_URL:="${INSTALL_JAVA_ROOTURL}/jdk-${url_version}/OpenJDK${INSTALL_JAVA_MAIN_VERSION}U-jdk_${arch}_${os}_hotspot_${file_version}.tar.gz"}"
: "${INSTALL_JAVA_SUMS:="${INSTALL_JAVA_URL}.sha256.txt"}"


log_init INSTALL


if ! command_present "java" && [ -n "$INSTALL_JAVA_VERSION" ]; then
  trace "Installing Java %s from %s" "$INSTALL_JAVA_VERSION" "$INSTALL_JAVA_URL"
  # Download and install
  internet_tgz_installer \
    "$INSTALL_JAVA_URL" \
    "${INSTALL_PREFIX}/share/java" \
    "java" \
    "$INSTALL_JAVA_SUMS"
  for _bin in "${INSTALL_PREFIX}/share/java/jdk-${INSTALL_JAVA_VERSION}/bin"/*; do
    [ -x "$_bin" ] || continue
    as_root chmod a+x "$_bin"
    as_root ln -sf "$_bin" "${INSTALL_PREFIX}/bin/$(basename "$_bin")"
  done

  verbose "Installed Java %s inside %s. Running version: %s" \
    "$INSTALL_JAVA_VERSION" \
    "${INSTALL_PREFIX}/share/java" \
    "$("${INSTALL_PREFIX}/bin/java" --version)"
fi
