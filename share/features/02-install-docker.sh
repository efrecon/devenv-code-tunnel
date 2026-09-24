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
    if [ -z "$INSTALL_DOCKER_SHA512" ]; then
      _cert=$(extract_cert "$INSTALL_DOCKER_URL" "" 0 || true)
      if [ -n "$_cert" ]; then
        CN=$(openssl x509 -in "$_cert" -noout -subject -nameopt multiline | awk -F'= ' '/commonName/ {print $2}')
        rm -f "$_cert"
        if printf '%s\n' "$CN" | grep -qE 'docker.com$'; then
          _raw=$(mktemp) && download "$INSTALL_DOCKER_RAW" "$_raw"
          _official=$(mktemp) && download "$INSTALL_DOCKER_URL" "$_official"
          trace "Comparing downloaded install script with the raw version %s %s" "$_raw" "$_official"
          # Count positional header lines
          diff_count=$(diff "$_raw" "$_official" | grep -c '^[0-9]' || true)
          # 1 line is ok, the SHA is inserted at CI time.
          if [ "$diff_count" -gt 1 ]; then
            error "The downloaded install script differs from the raw version by $diff_count lines"
          else
            verbose "The downloaded install script matches the raw version"
          fi
          rm -f "$_raw" "$_official"
          verbose "Certificate common name matches docker.com: $CN"
        else
          error "Certificate common name does not match docker.com: $CN"
        fi
      else
        error "Failed to extract certificate from $INSTALL_DOCKER_URL"
      fi
    fi
    as_root internet_script_installer "$INSTALL_DOCKER_URL" docker "$INSTALL_DOCKER_SHA512"
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
