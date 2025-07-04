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


log_init INSTALL


if ! command_present "aws"; then
  # Install the AWS CLI. This will bring a large number of python
  # dependencies...
  if is_os_family alpine; then
    install_packages aws-cli
  elif is_os_family debian; then
    install_packages awscli
  else
    error "Unsupported OS family: %s" "$(get_distro_name)"
  fi
  verbose "Installed aws CLI: $(aws --version)"
  install_ondemand<<EOF
mandoc
EOF

  # If npm is installed, then install the AWS CDK.
  if ! command_present cdk && command_present npm; then
    debug "Installing cdk"
    as_root npm install -g cdk
    verbose "Installed cdk: $(cdk --version)"
  else
    debug "cdk already installed"
  fi
fi
