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


log_init INSTALL


if ! check_command "aws"; then
  # Install the AWS CLI. This will bring a large number of python
  # dependencies...
  install_packages aws-cli
  verbose "Installed aws CLI: $(aws --version)"
  install_ondemand<<EOF
mandoc
EOF

  # If npm is installed, then install the AWS CDK.
  if ! check_command cdk && check_command npm; then
    verbose "Installing cdk"
    as_root npm install -g cdk
    verbose "Installed cdk: $(cdk --version)"
  else
    verbose "cdk already installed"
  fi
fi
