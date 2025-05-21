#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

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
: "${INSTALL_PREFIX:="/usr/local"}"
: "${INSTALL_USER_PREFIX:="${HOME}/.local"}"
: "${INSTALL_TARGET:="user"}"

: "${INSTALL_GITHUB_VERSION:="2.73.0"}"
: "${INSTALL_GITHUB_URL:="https://github.com/cli/cli/releases/download/v${INSTALL_GITHUB_VERSION}/gh_${INSTALL_GITHUB_VERSION}_$(get_os)_$(get_golang_arch).tar.gz"}"
: "${INSTALL_GITHUB_SUMS:="https://github.com/cli/cli/releases/download/v${INSTALL_GITHUB_VERSION}/gh_${INSTALL_GITHUB_VERSION}_checksums.txt"}"

: "${INSTALL_GITLAB_VERSION:="1.57.0"}"
: "${INSTALL_GITLAB_URL:="https://gitlab.com/gitlab-org/cli/-/releases/v${INSTALL_GITLAB_VERSION}/downloads/glab_${INSTALL_GITLAB_VERSION}_$(get_os)_$(get_golang_arch).tar.gz"}"
: "${INSTALL_GITLAB_SUMS:="https://gitlab.com/gitlab-org/cli/-/releases/v${INSTALL_GITLAB_VERSION}/downloads/checksums.txt"}"

: "${INSTALL_TEA_VERSION:="0.9.2"}"
: "${INSTALL_TEA_URL:="https://dl.gitea.com/tea/${INSTALL_TEA_VERSION}/tea-${INSTALL_TEA_VERSION}-$(get_os)-$(get_golang_arch)"}"
: "${INSTALL_TEA_SUM:="https://dl.gitea.com/tea/${INSTALL_TEA_VERSION}/tea-${INSTALL_TEA_VERSION}-$(get_os)-$(get_golang_arch).sha256"}"

log_init INSTALL


# Decide target directory for the installations, based on the INSTALL_TARGET
# preference.
[ "$INSTALL_TARGET" = "user" ] \
  && BINDIR="${INSTALL_USER_PREFIX}/bin" \
  || BINDIR="${INSTALL_PREFIX}/bin"

# Install the various CLIs using our installation functions.
for forge in \
  "github|$INSTALL_GITHUB_URL|$INSTALL_GITHUB_SUMS|internet_bintgz_installer|gh" \
  "gitlab|$INSTALL_GITLAB_URL|$INSTALL_GITLAB_SUMS|internet_bintgz_installer|glab" \
  "gitea|$INSTALL_TEA_URL|$INSTALL_TEA_SUM|internet_bin_installer|tea"; do
  IFS="|" read -r name url sums installer cmd <<EOF
$forge
EOF
  debug "Installing %s CLI in %s..." "$name" "$BINDIR"
  bin=$($installer "$url" "$BINDIR" "$cmd" "$sums")
  verbose "Installed %s CLI %s" "$name" "$("$bin" --version)"
done
