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

# Install from source
: "${INSTALL_NODE_FROM_SOURCE:="auto"}"

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

build_from_source() {
  verbose "Downloading and building Node.js %s from source" "$1"
  curdir=$(pwd)
  builddir=$(mktemp -d)
  cd "$builddir"

  # Download the source tarball and the SHA256 sum file
  download "https://nodejs.org/dist/v${1}/node-v${1}.tar.gz" "node-v${1}.tar.gz"
  download "https://nodejs.org/dist/v${1}/SHASUMS256.txt.asc" "SHASUMS256.txt.asc"

  # Add build dependencies
  as_root apk add --no-cache --virtual .build-deps-full \
      binutils-gold \
      g++ \
      gcc \
      gnupg \
      libgcc \
      linux-headers \
      make \
      python3 \
      py-setuptools

  # use pre-existing gpg directory, see https://github.com/nodejs/docker-node/pull/1895#issuecomment-1550389150
  GNUPGHOME="$(mktemp -d)"
  export GNUPGHOME
  # gpg keys listed at https://github.com/nodejs/node#release-keys
  for key in \
    C0D6248439F1D5604AAFFB4021D900FFDB233756 \
    DD792F5973C6DE52C432CBDAC77ABFA00DDBF2B7 \
    CC68F5A3106FF448322E48ED27F5E38D5B0A215F \
    8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
    890C08DB8579162FEE0DF9DB8BEAB4DFCF555EF4 \
    C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
    108F52B48DB57BB0CC439B2997B01419BD92F80A \
    A363A499291CBBC940DD62E41F10027AF002F8B0 \
  ; do
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" ||
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key"
  done

  # Decrypt the SHA256 sum file and verify the tarball
  gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc
  gpgconf --kill all
  rm -rf "$GNUPGHOME"
  grep " node-v${1}.tar.gz\$" SHASUMS256.txt | sha256sum -c -

  # Unpack, build and install into the proper location
  tar -xf "node-v${1}.tar.gz"
  cd "node-v${1}"
  ./configure --prefix="$INSTALL_PREFIX"
  make -j"$(getconf _NPROCESSORS_ONLN)" V=
  as_root make install
  as_root apk del .build-deps-full

  cd "$curdir"
  rm -rf "$builddir"
}


if ! check_command "node" && [ -n "$INSTALL_NODE_VERSION" ]; then
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

  if [ "$INSTALL_NODE_FROM_SOURCE" = "auto" ]; then
    # When using the unofficial builds, we need to add the libc type to the OS.
    if [ "$INSTALL_NODE_DOMAIN" = "unofficial-builds.nodejs.org" ]; then
      arch=$(get_arch)
      verbose "Installing Node.js %s for %s %s" "$latest" "$(get_os)" "$arch"
      if is_musl_os; then
        # musl builds are only available for x64
        if [ "$arch" = "x64" ]; then
          INSTALL_TGZURL="${INSTALL_ROOTURL}/${latest}/node-${latest}-$(get_os)-${arch}-musl.tar.xz"
        else
          verbose "No binaries available for %s and musl, will build from source" "$arch"
          INSTALL_TGZURL=
        fi
      else
        INSTALL_TGZURL="${INSTALL_ROOTURL}/${latest}/node-${latest}-$(get_os)-${arch}-glibc.tar.gz"
      fi
    else
      INSTALL_TGZURL="${INSTALL_ROOTURL}/${latest}/node-${latest}-$(get_os)-${arch}.tar.gz"
    fi
  else
    INSTALL_TGZURL=
  fi

  if [ -z "$INSTALL_TGZURL" ]; then
    build_from_source "${latest#v}"
  else
    verbose "Downloading Node.js from: $INSTALL_TGZURL"
    # TODO: Verify sha256 sums through file SHASUMS256.txt from same URL.
    download "$INSTALL_TGZURL" | as_root tar -C "$INSTALL_PREFIX" -xzf - --strip-components 1 --exclude='*.md' --exclude='LICENSE'
  fi
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
