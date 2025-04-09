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

# User that the container will run as. Will be member of docker group and able
# to sudo without password. Specify this as user or user:group, when the group
# is missing, it will be the same as the user.
: "${INSTALL_USER:="coder"}"

# When a dash, do not try to optimize disk access. When empty (the default) will
# download, install and use eatmydata. When anything else, will prefix
# installation calls with the content of this var.
: "${INSTALL_OPTIMIZE:=""}"

# Prefix where to install binaries and libraries.
: "${INSTALL_PREFIX:="/usr/local"}"

# Features to install. For each feature, there must be a install-<feature>.sh
# script in the share/features directory. The script will be called to install
# the feature, it will automatically inherit all INSTALL_ variables. When empty,
# all features will be installed. When a dash, no feature will be installed.
: "${INSTALL_FEATURES:=""}"

# Build of vscode to install: only stable or insiders are available.
: "${INSTALL_CODE_BUILD:="stable"}"

# URL to download the code CLI from.
: "${INSTALL_CODE_URL:="https://code.visualstudio.com/sha/download?build=${INSTALL_CODE_BUILD}&os=cli-alpine-x64"}"

# Declared here, used in common.sh library.
INSTALL_REPOS_SHA256=

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


install_code() {
  verbose "Installing code CLI"
  download "$INSTALL_CODE_URL" /tmp/code.tar.gz
  tmp=$(mktemp -d)
  tar -C "$tmp" -zxvf /tmp/code.tar.gz
  find "$tmp" -name 'code*' -exec mv -f \{\} "${INSTALL_PREFIX}/bin/code" \;
  rm -rf "$tmp"
  install_packages "libstdc++"
}


list_features() {
  find "$1" -name '*install-*.sh' |
    sort |
    sed -e 's|.*/.*install-\(.*\)\.sh|\1|' |
    tr '\n' ' '
}


get_feature() {
  find "$1" -name "*install-$2.sh"
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
# presence of the (main/some) command that they install in most cases.
install_ondemand<<EOF
curl
zip
jq
git
git-lfs
bash
less
- gcompat
EOF

create_user "$INSTALL_USER"
mkdir -p "$INSTALL_PREFIX"/log
chown -R "$INSTALL_USER" "$INSTALL_PREFIX"/log

install_code

# Export all variables that start with INSTALL_ so that they are available
# to the features that are installed.
while IFS= read -r varset; do
  export "$(printf %s\\n "$varset" | cut -d= -f1)"
done <<EOF
$(set | grep '^INSTALL_')
EOF


# Find out where the features directory is.
for d in "${INSTALL_ROOTDIR}/share/features" "${INSTALL_PREFIX}/share/features"; do
  if [ -d "$d" ]; then
    FEATURES_DIR=$d
    break
  fi
done

# Look for all features to install
if [ -z "$INSTALL_FEATURES" ]; then
  INSTALL_FEATURES=$(list_features "$FEATURES_DIR")
  verbose "Installing all features: %s" "$INSTALL_FEATURES"
fi

# Install all required features, unless told not to.
if [ "$INSTALL_FEATURES" != "-" ]; then
  for feature in $INSTALL_FEATURES; do
    script=$(get_feature "$FEATURES_DIR" "$feature")
    if [ -z "$script" ]; then
      warn "Feature %s not found in %s" "$feature" "$FEATURES_DIR"
      continue
    fi
    if [ -x "$script" ]; then
      verbose "Installing feature: $feature"
      $INSTALL_OPTIMIZE "$script"
    fi
  done
fi


# Clean repository cache
apk cache clean
rm -rf /var/cache/apk/*
