#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

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

: "${INSTALL_TAILCAT_VERSION:="0.6.0"}"
INSTALL_TAILCAT_VERSION=${INSTALL_TAILCAT_VERSION#v}; # Remove leading v, if any

# URL to download the code CLI from.
: "${INSTALL_TAILCAT_URL:="https://github.com/tailscale/tailcat/releases/download/v${INSTALL_TAILCAT_VERSION}/tailcat_${INSTALL_TAILCAT_VERSION}_$(get_os)_$(get_golang_arch).tar.gz"}"
: "${INSTALL_TAILCAT_SUMS:="https://github.com/tailscale/tailcat/releases/download/v${INSTALL_TAILCAT_VERSION}/checksums.txt"}"


log_init INSTALL


debug "Installing tailcat v%s" "$INSTALL_TAILCAT_VERSION"

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
tailcat=$(internet_bintgz_installer \
                "$INSTALL_TAILCAT_URL" \
                "$BINDIR" \
                "tailcat" \
                "$INSTALL_TAILCAT_SUMS")

# Verify installation through printing the version.
verbose "Installed tailcat %s" "$("$tailcat" --version)"

