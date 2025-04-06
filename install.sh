#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the common library
for d in ../lib lib; do
  if [ -d "${INSTALL_ROOTDIR}/$d" ]; then
    # shellcheck disable=SC1091 source=lib/common.sh
    . "${INSTALL_ROOTDIR}/$d/common.sh"
    break
  fi
done

# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at INSTALL_LOG.
: "${INSTALL_VERBOSE:=0}"

# Where to send logs
: "${INSTALL_LOG:=2}"

# User that the container will run as. Will be member of docker group and able to
# sudo without password.
: "${INSTALL_USER:="coder"}"

# When dash, do not try to optimize disk access, when empty will download,
# install and use eatmydata. When anything else, will prefix installation calls
# with this var.
: "${INSTALL_OPTIMIZE:=""}"

: "${INSTALL_PREFIX:="/usr/local"}"

: "${INSTALL_FEATURES:="sudo"}"

# stable or insiders
: "${INSTALL_CODE_BUILD:="stable"}"

: "${INSTALL_CODE_URL:="https://code.visualstudio.com/sha/download?build=${INSTALL_CODE_BUILD}&os=cli-alpine-x64"}"

CODER_DESCR="code container installer"
while getopts "l:u:vh" opt; do
  case "$opt" in
    u) # User or user:group to create
      INSTALL_USER="$OPTARG";;
    l) # Where to send logs
      INSTALL_LOG="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      INSTALL_VERBOSE=$((INSTALL_VERBOSE + 1));;
    h) # Show help
      usage 0 INSTALL
      ;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done

# Initialize
log_init INSTALL

create_user() {
  NEW_USER=$(printf %s\\n "$INSTALL_USER" | cut -d: -f1)
  NEW_GROUP=$(printf %s\\n "$INSTALL_USER" | cut -d: -f2)
  if grep -q "^$NEW_USER" /etc/passwd; then
    error "%s already exists!" "$NEW_USER"
  else
    addgroup "$NEW_GROUP"
    adduser \
      --disabled-password \
      --gecos "" \
      --shell "/bin/bash" \
      --ingroup "$NEW_GROUP" \
      "$NEW_USER"
  fi
}


install_docker() {
  verbose "installing docker"
  if ! check_command "docker"; then
    install_packages docker docker-cli-buildx docker-cli-compose fuse-overlayfs
  fi
  addgroup "docker" || warn "docker group already exists"
  NEW_USER=$(printf %s\\n "$INSTALL_USER" | cut -d: -f1)
  addgroup "$NEW_USER" "docker"
}

install_code() {
  verbose "Installing code CLI"
  download "$INSTALL_CODE_URL" /tmp/code.tar.gz
  tmp=$(mktemp -d)
  tar -C "$tmp" -zxvf /tmp/code.tar.gz
  find "$tmp" -name 'code*' -exec mv -f \{\} /usr/local/bin/code \;
  rm -rf "$tmp"
  install_packages "libstdc++"
}


######################################################################
# Let's start the installation process. This is the main part of the script.
######################################################################


# Early install of eatmydata to minimize disk access during the installation
# process.
if [ "$INSTALL_OPTIMIZE" = "-" ]; then
  # When dash, do not try to optimize disk access
  INSTALL_OPTIMIZE=""
elif [ -z "$INSTALL_OPTIMIZE" ]; then
  install_packages libeatmydata
  INSTALL_OPTIMIZE="eatmydata"
fi

# Install package that we need ourselves. Trigger installation based on the
# presence of the (main/some) command that they install.
while read -r bin pkg; do
  [ -z "$pkg" ] && pkg=$bin
  if [ -n "${bin:-}" ] && ! check_command "$bin"; then
    verbose "$bin not found, installing $pkg"
    install_packages "$pkg"
  fi
done <<EOF
curl
unzip
jq
git
git-lfs
bash
EOF

create_user
install_docker
install_code

for feature in $INSTALL_FEATURES; do
  if [ -x "${INSTALL_PREFIX}/install-${feature}.sh" ]; then
    verbose "Installing feature: $feature"
    $INSTALL_OPTIMIZE "${INSTALL_PREFIX}/install-${feature}.sh"
  fi
done
