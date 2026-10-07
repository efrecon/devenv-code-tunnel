#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Absolute location of the script where this script is located.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common system install; do
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

: "${INSTALL_DOCKER_URL:="https://get.docker.com"}"
: "${INSTALL_DOCKER_RAW:="https://github.com/docker/docker-install/raw/refs/heads/master/install.sh"}"
: "${INSTALL_DOCKER_SHA512:=""}"

log_init INSTALL


verbose "installing docker"
if ! command_present "docker"; then
  if is_os_family alpine; then
    install_packages docker docker-cli-buildx docker-cli-compose fuse-overlayfs
  else
    _official=$(mktemp)
    download "$INSTALL_DOCKER_URL" "$_official"

    if [ -n "$INSTALL_DOCKER_SHA512" ]; then
      checksum "$_official" "$INSTALL_DOCKER_SHA512" "docker install script"
    else
      # Extract the commit SHA published inside the official script
      commit_sha=$(sed -n 's/^SCRIPT_COMMIT_SHA="*\([a-f0-9]\{40\}\)"*/\1/p' "$_official")

      if [ -z "$commit_sha" ]; then
        rm -f "$_official"
        error "Could not extract SCRIPT_COMMIT_SHA from $INSTALL_DOCKER_URL"
      fi

      # Download the exact commit from GitHub for cross-verification
      _raw=$(mktemp)
      raw_url="https://raw.githubusercontent.com/docker/docker-install/${commit_sha}/install.sh"
      download "$raw_url" "$_raw"

      # Ensure the ONLY difference is the SCRIPT_COMMIT_SHA assignment line
      unexpected_diff=$(diff -u "$_raw" "$_official" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---|[+-]SCRIPT_COMMIT_SHA=)' || true)
      rm -f "$_raw"

      if [ -n "$unexpected_diff" ]; then
        rm -f "$_official"
        error "The downloaded install script contains unexpected modifications compared to GitHub commit $commit_sha"
      fi

      verbose "Script successfully cross-verified against GitHub commit $commit_sha"
    fi

    # Execute the already-verified local file (avoids TOCTOU re-download)
    as_root sh "$_official"
    rm -f "$_official"
  fi
fi

# Create the docker group if it does not exist
if ! getent group "docker" > /dev/null; then
  debug "Creating docker group"
  as_root addgroup "docker" || warn "Cannot create docker group"
else
  trace "Docker group already exists"
fi

# Add the user to the docker group
if [ -n "$INSTALL_USER" ]; then
  USR=$(printf %s\\n "$INSTALL_USER" | cut -d: -f1)
  if is_os_family alpine; then
    as_root addgroup "$USR" "docker"
  else
    groupmod -aU "$USR" docker || warn "Cannot add user $USR to docker group"
  fi
else
  warn "No user specified, docker will not be configured"
fi
