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

: "${INSTALL_FEATURES:="sudo docker"}"

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

for feature in $INSTALL_FEATURES; do
  for d in "${INSTALL_ROOTDIR}/share/features" "${INSTALL_PREFIX}/share/features"; do
    if [ -d "$d" ] && [ -x "${d}/install-${feature}.sh" ]; then
      verbose "Installing feature: $feature"
      $INSTALL_OPTIMIZE "${d}/install-${feature}.sh"
      break
    fi
  done
done
