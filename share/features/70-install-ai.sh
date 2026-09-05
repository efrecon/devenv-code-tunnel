#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

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
: "${INSTALL_CLAUDE_ROOT:="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"}"

log_init INSTALL

# Decide target directory for the installations, based on the INSTALL_TARGET
# preference.
[ "$INSTALL_TARGET" = "user" ] \
  && BINDIR="${INSTALL_USER_PREFIX}/bin" \
  || BINDIR="${INSTALL_PREFIX}/bin"

if [ "$INSTALL_CLAUDE_VERSION" = "latest" ]; then
  INSTALL_CLAUDE_VERSION=$(download "$INSTALL_CLAUDE_ROOT/latest")
  verbose "Latest claude version: %s" "$INSTALL_CLAUDE_VERSION"
fi

if is_musl_os; then
  platform=$(get_os)-$(get_arch)-musl
else
  platform=$(get_os)-$(get_arch)
fi
internet_bin_installer \
  "${INSTALL_CLAUDE_ROOT}/${INSTALL_CLAUDE_VERSION}/${platform}/claude" \
  "$BINDIR" \
  "claude"
verbose "Installed claude version %s to %s/claude" "$("$BINDIR/claude" --version)" "$BINDIR"
