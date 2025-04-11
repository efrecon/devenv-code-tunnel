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

# All following vars have defaults here, but will be set and inherited from
# calling install.sh script in the normal case.
: "${INSTALL_VERBOSE:=0}"
: "${INSTALL_LOG:=2}"
: "${INSTALL_USER:="coder"}"
: "${INSTALL_PREFIX:="/usr/local"}"
: "${INSTALL_USER_PREFIX:="${HOME}/.local"}"
: "${INSTALL_TARGET:="user"}"

# Version of Node.js to install. Empty to disable. This will match as much as
# you want, e.g. 10 or 10.12, etc.
: "${INSTALL_NODE_VERSION:=22}"

# Where to download the Node.js tarball from. The default is empty, which will
# switch to the unofficial builds when running on musl.
: "${INSTALL_NODE_DOMAIN:=""}"

# Type of the builds to download. rc or release. The default is release.
: "${INSTALL_NODE_TYPE:="release"}"

# node-based apps to install. This is a space separated list of apps to install.
: "${INSTALL_NODE_APPS:="bun"}"



log_init INSTALL



node_version() {
  download "${INSTALL_ROOTURL}/index.tab" |
    grep "^v${INSTALL_NODE_VERSION}" |
    awk '/^v[0-9]/{ print $1; exit }'
}


if ! check_command "node" && [ -n "$INSTALL_NODE_VERSION" ]; then
  # Convert the local architecture to the one used by Node.js. Note: some of
  # these do not use musl.
  arch=$(uname -m)
  [ "$arch" = "x86_64" ] && arch="x64"
  [ "$arch" = "x686" ] && arch="x86"
  [ "$arch" = "aarch64" ] && arch="arm64"

  # OS name. This really has only been tested on linux...
  os=$(uname | to_lower)

  # Find out where to get the tarball from. This will switch to the unofficial
  # builds when running on musl.
  if [ -z "$INSTALL_NODE_DOMAIN" ]; then
    if is_musl_os; then
      INSTALL_NODE_DOMAIN="unofficial-builds.nodejs.org"
    else
      INSTALL_NODE_DOMAIN="nodejs.org"
    fi
  fi

  # Main URL to download node files from.
  INSTALL_ROOTURL="https://${INSTALL_NODE_DOMAIN}/download/${INSTALL_NODE_TYPE}"

  # Find out the version out of the official ones
  assert_version "$INSTALL_NODE_VERSION"
  latest=$(node_version)
  verbose "Installing Node $latest"

  # When using the unofficial builds, we need to add the libc type to the OS.
  if [ "$INSTALL_NODE_DOMAIN" = "unofficial-builds.nodejs.org" ]; then
    if is_musl_os; then
      INSTALL_TGZURL="${INSTALL_ROOTURL}/${latest}/node-${latest}-${os}-${arch}-musl.tar.gz"
    else
      INSTALL_TGZURL="${INSTALL_ROOTURL}/${latest}/node-${latest}-${os}-${arch}-glibc.tar.gz"
    fi
  else
    INSTALL_TGZURL="${INSTALL_ROOTURL}/${latest}/node-${latest}-${os}-${arch}.tar.gz"
  fi

  verbose "Downloading Node.js from: $INSTALL_TGZURL"
  # TODO: Verify sha256 sums through file SHASUMS256.txt from same URL.
  download "$INSTALL_TGZURL" | as_root tar -C "$INSTALL_PREFIX" -xzf - --strip-components 1 --exclude='*.md' --exclude='LICENSE'
  verbose "Installed Node: $(node --version)"

  # Upgrade and prepare package managers
  as_root npm update -g npm
  as_root npm install -g corepack
  as_root corepack enable
  as_root corepack prepare yarn@stable --activate
  as_root corepack prepare pnpm@latest --activate

  # Install the node-based apps
  for app in $INSTALL_NODE_APPS; do
    if ! check_command "$app"; then
      verbose "Installing $app"
      as_root npm install -g "$app"
    else
      verbose "$app already installed"
    fi
  done
fi
