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

# Prefix where to install the cli. We have a default here, but the main prefix
# comes from the calling install.sh.
: "${INSTALL_PREFIX:="/usr/local"}"

# Root URL where to find the cli
: "${INSTALL_AWSURL:="https://awscli.amazonaws.com"}"

# Version to install, empty for latest. For known versions, check:
# https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst
: "${INSTALL_AWSCLI_VERSION:=""}"

log_init INSTALL


if ! check_command "aws"; then
  arch=$(uname -m)
  # OS name. This really has only been tested on linux...
  os=$(uname | to_lower)
  if [ -z "${INSTALL_AWSCLI_VERSION:-}" ]; then
    INSTALL_ZIPURL="${INSTALL_AWSURL%/}/awscli-exe-${os}-${arch}.zip"
  else
    assert_version "$INSTALL_AWSCLI_VERSION"
    INSTALL_ZIPURL="${INSTALL_AWSURL%/}/awscli-exe-${os}-${arch}-${INSTALL_AWSCLI_VERSION}.zip"
  fi

  verbose "Installing AWS CLI"
  download "$INSTALL_ZIPURL" /tmp/awscliv2.zip
  # Work in a separate directory to avoid cluttering the current one, do that in
  # a separate process so we don't loose the current working dir.
  (
    cd /tmp
    unzip awscliv2.zip
    as_root ./aws/install \
                --update \
                --bin-dir "$INSTALL_PREFIX/bin" \
                --install-dir "$INSTALL_PREFIX/share/awscli"
    rm -rf aws awscliv2.zip
  )
  verbose "Installed aws CLI: $(aws --version)"
fi
