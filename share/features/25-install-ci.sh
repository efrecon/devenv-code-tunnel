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
    if [ -d "${INSTALL_ROOTDIR}/$d" ] && [ -f "${INSTALL_ROOTDIR}/$d/${lib}.sh" ]; then
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

# TeamCity and Harness name their x86_64 releases after uname, not golang.
: "${INSTALL_TEAMCITY_VERSION:="1.6.3"}"
: "${INSTALL_TEAMCITY_URL:="https://github.com/JetBrains/teamcity-cli/releases/download/v${INSTALL_TEAMCITY_VERSION}/teamcity_${INSTALL_TEAMCITY_VERSION}_$(get_os)_$(get_golang_arch x86_64 x86_64).tar.gz"}"
: "${INSTALL_TEAMCITY_SUMS:="https://github.com/JetBrains/teamcity-cli/releases/download/v${INSTALL_TEAMCITY_VERSION}/checksums.txt"}"

: "${INSTALL_BUILDKITE_VERSION:="3.67.0"}"
: "${INSTALL_BUILDKITE_URL:="https://github.com/buildkite/cli/releases/download/v${INSTALL_BUILDKITE_VERSION}/bk_${INSTALL_BUILDKITE_VERSION}_$(get_os)_$(get_golang_arch).tar.gz"}"
: "${INSTALL_BUILDKITE_SUMS:="https://github.com/buildkite/cli/releases/download/v${INSTALL_BUILDKITE_VERSION}/bk_${INSTALL_BUILDKITE_VERSION}_checksums.txt"}"

: "${INSTALL_CIRCLECI_VERSION:="1.13.0"}"
: "${INSTALL_CIRCLECI_URL:="https://github.com/CircleCI-Public/circleci-cli/releases/download/v${INSTALL_CIRCLECI_VERSION}/circleci-cli_${INSTALL_CIRCLECI_VERSION}_$(get_os)_$(get_golang_arch).tar.gz"}"
: "${INSTALL_CIRCLECI_SUMS:="https://github.com/CircleCI-Public/circleci-cli/releases/download/v${INSTALL_CIRCLECI_VERSION}/circleci-cli_${INSTALL_CIRCLECI_VERSION}_checksums.txt"}"

: "${INSTALL_HARNESS_VERSION:="1.3.47"}"
: "${INSTALL_HARNESS_URL:="https://github.com/harness/harness-cli/releases/download/v${INSTALL_HARNESS_VERSION}/hc_${INSTALL_HARNESS_VERSION}_$(get_os)_$(get_golang_arch x86_64 x86_64).tar.gz"}"
: "${INSTALL_HARNESS_SUMS:="https://github.com/harness/harness-cli/releases/download/v${INSTALL_HARNESS_VERSION}/checksums.txt"}"

log_init INSTALL


# Decide target directory for the installations, based on the INSTALL_TARGET
# preference.
[ "$INSTALL_TARGET" = "user" ] \
  && BINDIR="${INSTALL_USER_PREFIX}/bin" \
  || BINDIR="${INSTALL_PREFIX}/bin"

# Install the various CLIs using our installation functions. The last field is
# how to get the version of the CLI, which differs between CLIs.
for ci in \
  "teamcity|$INSTALL_TEAMCITY_URL|$INSTALL_TEAMCITY_SUMS|teamcity|--version" \
  "buildkite|$INSTALL_BUILDKITE_URL|$INSTALL_BUILDKITE_SUMS|bk|--version" \
  "harness|$INSTALL_HARNESS_URL|$INSTALL_HARNESS_SUMS|hc|version"; do
  IFS="|" read -r name url sums cmd version <<EOF
$ci
EOF
  debug "Installing %s CLI in %s..." "$name" "$BINDIR"
  bin=$(internet_bintgz_installer "$url" "$BINDIR" "$cmd" "$sums")
  verbose "Installed %s CLI %s" "$name" "$("$bin" "$version" | head -n 1)"
done

# The CircleCI tarball also carries a bash completion file called circleci, so
# only extract the binary at the root of the tarball.
debug "Installing circleci CLI in %s..." "$BINDIR"
internet_tgz_installer \
  "$INSTALL_CIRCLECI_URL" \
  "$BINDIR" \
  "circleci" \
  "$INSTALL_CIRCLECI_SUMS" \
  circleci
verbose "Installed circleci CLI %s" "$("${BINDIR}/circleci" version)"
