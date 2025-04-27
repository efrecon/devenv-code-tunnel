#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common install system; do
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

# Where should we install from. This is either "auto" (default), "image" or
# "source". When "image" compiled binaries will be picked from an existing
# image.
: "${INSTALL_NODE_SOURCE:="auto"}"

# Docker registry to use for the image when installing binaries out of an
# existing image. Possible other values are: mirror.gcr.io or
# public.ecr.aws/docker
: "${INSTALL_NODE_REGISTRY:="docker.io"}"

# Name of the node image to use when installing binaries out of an existing
# image.
: "${INSTALL_NODE_IMAGE:="library/node"}"

: "${INSTALL_NODE_REGCLIENT_VERSION:="0.8.2"}"

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
  if ! check_command corepack; then
    # Upgrade and prepare package managers
    verbose "Installing and enabling corepack"
    "$@" npm install -g corepack
    "$@" corepack enable
  fi
  if ! check_command yarn; then
    verbose "Installing yarn"
    "$@" corepack prepare yarn@stable --activate
  fi
  if ! check_command pnpm; then
    verbose "Installing pnpm"
    "$@" corepack prepare pnpm@latest --activate
  fi

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

# Building node from source takes a long time, as in several hours when running
# in GitHub actions.
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

  # Unpack
  trace "Extracting Node.js from %s" "node-v${1}.tar.gz"
  tar -xzf "node-v${1}.tar.gz"

  # Build and install into the proper location
  trace "Configuring Node.js %s. Installation prefix: %s" "$1" "$INSTALL_PREFIX"
  cd "node-v${1}"
  ./configure --prefix="$INSTALL_PREFIX"
  make -j"$(getconf _NPROCESSORS_ONLN)" V=
  as_root make install
  as_root apk del .build-deps-full

  cd "$curdir"
  rm -rf "$builddir"
}


# Install regclient https://regclient.org/ in order to be able to extract the
# content of docker files without the docker client installed (and without the
# docker daemon running: at installation time, the daemon is not running yet).
install_regclient() {
  arch=$(get_arch x86_64 amd64)
  regclient_url=https://github.com/regclient/regclient/releases/download/v${INSTALL_NODE_REGCLIENT_VERSION}/regctl-$(get_os)-${arch}
  download "$regclient_url" > "${INSTALL_PREFIX}/bin/regctl"
  chmod a+x "${INSTALL_PREFIX}/bin/regctl"
}


# Install Node.js from a docker image, this will match the version of node onto
# an image for the current OS, if possible.
install_from_image() {
  # Find out the part of the tag that matches the current OS, if possible.
  distro=$(get_distro_name)
  case "$distro" in
    alpine)
      # Tags only use major.minor for the version of alpine.
      os_tag="${distro}$(printf %s\\n "$(get_distro_version)"|grep -Eo '^[0-9]+\.[0-9]+')";;
    debian)
      # Pick the slim version for debian, as we just want to copy as little as
      # possible.
      os_tag="$(get_release_info VERSION_CODENAME)-slim";;
    *)
      # Can we do something about debian-derivatives?
      error "Unsupported distribution: %s" "$distro";;
  esac
  tag="${1}-${os_tag}"

  # install regctl if not already installed
  check_command "regctl" || install_regclient

  # Extract content of (remote) image to a temporary directory, for the current
  # platform.
  img=${INSTALL_NODE_REGISTRY%/}/${INSTALL_NODE_IMAGE}:$tag
  verbose "Extracting node v%s from image %s" "$1" "$img"
  imgdir=$(mktemp -d)
  regctl image export --platform local "$img" | tar -C "$imgdir" -xf -

  # Find the largest tar file in the image, it's where node is. Its name is a 64
  # character hexadecimal string. The pattern pads 0 with 64 leading zeros and
  # replaces the 0 with [0-9a-fA-F] to match the tar file name.
  ptn=$(printf "%0*d" 64 "0"|sed 's/0/[0-9a-fA-F]/g')
  layer=$(find "$imgdir" -type f -name "$ptn" -exec du -b {} + | sort -n | tail -1 | cut -f2)

  # Extract it to another temp directory
  layerdir=$(mktemp -d)
  tar -C "$layerdir" -xf "$layer"
  chmod -R a+r "$layerdir"
  rm -rf "$imgdir";  # Micro optimize disk space: remove the image directory

  # Copy the content of the usr/local directory into our target prefix
  as_root cp -r "$layerdir"/usr/local/* "$INSTALL_PREFIX"

  # Install dependencies
  install_packages \
    libstdc++ \
    libgcc

  # Clean up
  rm -rf "$layerdir"
  verbose "Installed Node.js %s from image %s" "$1" "$tag"
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

  if [ "$INSTALL_NODE_SOURCE" = "auto" ]; then
    # When using the unofficial builds, we need to add the libc type to the OS.
    if [ "$INSTALL_NODE_DOMAIN" = "unofficial-builds.nodejs.org" ]; then
      arch=$(get_arch)
      verbose "Installing Node.js %s for %s %s" "$latest" "$(get_os)" "$arch"
      if is_musl_os; then
        # musl builds are only available for x64
        if [ "$arch" = "x64" ]; then
          INSTALL_TGZURL="${INSTALL_ROOTURL}/${latest}/node-${latest}-$(get_os)-${arch}-musl.tar.gz"
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
    if [ "$INSTALL_NODE_SOURCE" = "image" ] || [ "$INSTALL_NODE_SOURCE" = "auto" ]; then
      install_from_image "${latest#v}"
    elif [ "$INSTALL_NODE_SOURCE" = "source" ]; then
      build_from_source "${latest#v}"
    else
      error "Don't know how to install Node.js %s" "$latest"
    fi
  else
    # Install dependencies
    install_packages \
      libstdc++ \
      libgcc
    verbose "Downloading Node.js from: $INSTALL_TGZURL"
    internet_tgz_installer \
      "$INSTALL_TGZURL" \
      "$INSTALL_PREFIX" \
      "node" \
      "${INSTALL_ROOTURL}/${latest}/SHASUMS256.txt" \
      --strip-components 1 --exclude='*.md' --exclude='LICENSE'
  fi
  verbose "Installed Node.js: $(node --version)"

  # Create user settings
  HM=$(home_dir "$INSTALL_USER")
  USR=$(printf %s\\n "$INSTALL_USER" | cut -d: -f1)
  touch "${HM}/.config/npmrc"
  ln -sf "${HM}/.config/npmrc" "${HM}/.npmrc"
  as_root chown "$INSTALL_USER" "${HM}/.npmrc" "${HM}/.config/npmrc"
  as_user "$USR" npm config set prefix "${INSTALL_USER_PREFIX}"
  verbose "npm installations for user %s under %s, as per %s" \
    "$USR" "$INSTALL_USER_PREFIX" "${HM}/.npmrc"

  # Create system settings
  mkdir -p "${INSTALL_PREFIX}/etc"
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
