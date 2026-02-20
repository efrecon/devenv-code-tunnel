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
: "${INSTALL_USER_PREFIX:="${HOME}/.local"}"
: "${INSTALL_TARGET:="user"}"

: "${INSTALL_CLAUDE_VERSION:="latest"}"
: "${INSTALL_CLAUDE_INSTALLER:="https://claude.ai/install.sh"}"
: "${INSTALL_CLAUDE_SHA512:="4f72071a0444fc5fdab0404b31c4e5f3618ed5af538b5d9f25ab0382a15227fff73c32ea08c1cb727373c5292615439a6b544a0c3d70dd4c14ee67d1bc75e014"}"

log_init INSTALL


internet_script_installer "$INSTALL_CLAUDE_INSTALLER" claude "$INSTALL_CLAUDE_SHA512" "$INSTALL_CLAUDE_VERSION"
verbose "Installed claude: $(claude --version)"
