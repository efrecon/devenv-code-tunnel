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

: "${INSTALL_GIT_LEFTHOOK_URL:="https://dl.cloudsmith.io/public/evilmartians/lefthook/setup.alpine.sh"}"
: "${INSTALL_GIT_LEFTHOOK_SHA512:="6c2b28a84501c4761a7a49dc4e4b71b580d8bf644675baa057928ff567bc611bdada62f7d2cbf2cd0150af62d2e94d2db0f3767ad9beadeb6ddf0e3a527313c4"}"

log_init INSTALL


install_ondemand<<EOF
git
git-lfs
pre-commit
lazygit
tig
gitui
git-annex
EOF

as_root internet_install "$INSTALL_GIT_LEFTHOOK_URL" dotnet "$INSTALL_GIT_LEFTHOOK_SHA512"
