#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common system; do
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
: "${INSTALL_CLOUDFLARED_URL:="https://github.com/cloudflare/cloudflared/releases/download/${INSTALL_CLOUDFLARED_VERSION}/cloudflared-$(get_os)-$(get_arch x86_64 amd64 i686 386)"}"

log_init INSTALL


verbose "Installing cloudflared v%s" "$INSTALL_CLOUDFLARED_VERSION"

install_ondemand<<EOF
nc netcat-openbsd
EOF

if [ "$INSTALL_TARGET" = "user" ]; then
  download "$INSTALL_CLOUDFLARED_URL" > "${INSTALL_USER_PREFIX}/bin/cloudflared"
  chmod +x "${INSTALL_USER_PREFIX}/bin/cloudflared"
  verbose "Installed cloudflared %s" "$("${INSTALL_USER_PREFIX}/bin/cloudflared" --version)"
else
  download "$INSTALL_CLOUDFLARED_URL" | as_root tee "${INSTALL_PREFIX}/bin/cloudflared" > /dev/null
  as_root chmod +x "${INSTALL_PREFIX}/bin/cloudflared"
  verbose "Installed cloudflared v%s" "$("${INSTALL_PREFIX}/bin/cloudflared" --version)"
fi

