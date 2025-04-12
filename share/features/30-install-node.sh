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
: "${INSTALL_NODE_APPS:="bun typescript ts-node tslint eslint prettier"}"



log_init INSTALL


# Guess latest node version matching INSTALL_NODE_VERSION
node_version() {
  download "${INSTALL_ROOTURL}/index.tab" |
    grep "^v${INSTALL_NODE_VERSION}" |
    awk '/^v[0-9]/{ print $1; exit }'
}


# Install package managers and node-based applications. The arguments are
# prepended, and should be one of the as_* functions, with arguments if
# relevant.
install_sidekicks() {
  verbose "Installing yarm and pnpm %s" "$(printf %s\\n "$*" | tr '_' ' ')"
  # Upgrade and prepare package managers
  "$@" npm install -g corepack
  "$@" corepack enable
  "$@" corepack prepare yarn@stable --activate
  "$@" corepack prepare pnpm@latest --activate

  # Install the node-based apps
  for app in $INSTALL_NODE_APPS; do
    if ! check_command "$app"; then
      verbose "Installing %s %s" "$app" "$(printf %s\\n "$*" | tr '_' ' ')"
      "$@" npm install -g "$app"
    else
      verbose "$app already installed %s" "$(printf %s\\n "$*" | tr '_' ' ')"
    fi
  done
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

  # Create user settings
  HM=$(home_dir "$INSTALL_USER")
  USR=$(printf %s\\n "$INSTALL_USER" | cut -d: -f1)
  touch "${HM}/.config/npmrc"
  ln -sf "${HM}/.config/npmrc" "${HM}/.npmrc"
  as_root chown "$INSTALL_USER" "${HM}/.npmrc" "${HM}/.config/npmrc"
  as_user "$USR" npm config set prefix "${INSTALL_USER_PREFIX}"
  verbose "npm installations for user %s user under %s, as per %s" \
    "$USR" "$INSTALL_USER_PREFIX" "${HM}/.npmrc"

  # Create system settings
  touch "${INSTALL_PREFIX}/etc/npmrc"
  as_root npm config -g set prefix "$INSTALL_PREFIX"
  verbose "System-wide npm installation under %s, as per %s" \
    "$INSTALL_PREFIX" "${INSTALL_PREFIX}/etc/npmrc"

  # Arrange to get the latest version of npm
  as_root npm update -g npm

  if [ "$INSTALL_TARGET" = "user" ]; then
    PATH="${INSTALL_USER_PREFIX}/bin:${PATH}"
    export PATH
    install_sidekicks as_user "$USR"
  else
    install_sidekicks as_root
  fi
fi
