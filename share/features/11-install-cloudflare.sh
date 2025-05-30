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

: "${INSTALL_CLOUDFLARED_VERSION:="2025.4.0"}"

# URL to download the code CLI from.
: "${INSTALL_CLOUDFLARED_URL:="https://github.com/cloudflare/cloudflared/releases/download/${INSTALL_CLOUDFLARED_VERSION}/cloudflared-$(get_os)-$(get_golang_arch)"}"
: "${INSTALL_CLOUDFLARED_SUMS:="https://github.com/cloudflare/cloudflared/releases/tag/${INSTALL_CLOUDFLARED_VERSION}"}"


log_init INSTALL


debug "Installing cloudflared v%s" "$INSTALL_CLOUDFLARED_VERSION"

# When started, our cloudflared wrapper will wait for a responding sshd. We will
# use nc.
install_ondemand<<EOF
nc netcat-openbsd
EOF

# Install the code CLI in the proper directory location, i.e. as per
# INSTALL_TARGET preference.
[ "$INSTALL_TARGET" = "user" ] \
  && BINDIR="${INSTALL_USER_PREFIX}/bin" \
  || BINDIR="${INSTALL_PREFIX}/bin"
cloudflared=$(internet_bin_installer \
                "$INSTALL_CLOUDFLARED_URL" \
                "$BINDIR" \
                "cloudflared" \
                "$INSTALL_CLOUDFLARED_SUMS")

# Verify installation through printing the version.
verbose "Installed cloudflared %s" "$("$cloudflared" --version)"

