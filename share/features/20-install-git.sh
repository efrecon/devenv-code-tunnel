#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

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


if is_os_family alpine; then
  : "${INSTALL_GIT_LEFTHOOK_URL:="https://dl.cloudsmith.io/public/evilmartians/lefthook/setup.alpine.sh"}"
  : "${INSTALL_GIT_LEFTHOOK_SHA512:="6c2b28a84501c4761a7a49dc4e4b71b580d8bf644675baa057928ff567bc611bdada62f7d2cbf2cd0150af62d2e94d2db0f3767ad9beadeb6ddf0e3a527313c4"}"
elif is_os_family debian; then
  : "${INSTALL_GIT_LEFTHOOK_URL:="https://dl.cloudsmith.io/public/evilmartians/lefthook/setup.deb.sh"}"
  : "${INSTALL_GIT_LEFTHOOK_SHA512:="ea55d4e4034dc0b3403d90cd17c7ee847214913db461cdf1f52596ea042bde738f6f77350078646a2793537133aca8895b90bf24cf45fa326e40d1997667b70e"}"
else
  : "${INSTALL_GIT_LEFTHOOK_URL:=""}"
  : "${INSTALL_GIT_LEFTHOOK_SHA512:=""}"
fi

: "${INSTALL_GIT_EXTRAS_URL:="https://raw.githubusercontent.com/tj/git-extras/main/install.sh"}"
: "${INSTALL_GIT_EXTRAS_SHA512:="915def79bb2f86448d5fad8542ceb3265cf4a99d95f2da4c6d9d07f1c16d1c26928f1579fa916ad20efe05f6cf55dbcc1c027cd753f1091f0aeb7e084ddf1c71"}"

log_init INSTALL


install_ondemand<<EOF
git
git-lfs
pre-commit
git-annex
EOF

# Dependencies of git-extras
if is_os_family alpine; then
  install_ondemand<<EOF
- util-linux-misc
EOF
elif is_os_family debian; then
  install_ondemand<<EOF
- bsdmainutils
EOF
else
  error "Unsupported OS family: %s" "$(get_distro_name)"
fi

if as_root internet_script_installer \
    "$INSTALL_GIT_LEFTHOOK_URL" \
    lefthook \
    "$INSTALL_GIT_LEFTHOOK_SHA512"; then
  install_packages lefthook
else
  warn "Failed to install lefthook using script at %s, skipping" "$INSTALL_GIT_LEFTHOOK_URL"
fi
if ! PREFIX="$INSTALL_PREFIX" as_root internet_script_installer \
      "$INSTALL_GIT_EXTRAS_URL" \
      git-extras \
      "$INSTALL_GIT_EXTRAS_SHA512"; then
  warn "Failed to install git-extras using script at %s, skipping" "$INSTALL_GIT_EXTRAS_URL"
fi
