#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
FORGES_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common system; do
  for d in ../../lib ../lib lib; do
    if [ -d "${FORGES_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${FORGES_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Arrange to set the CODER_BIN variable to the name of the script
bin_name


# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at FORGES_LOG.
: "${FORGES_VERBOSE:="${TUNNEL_VERBOSE:-"0"}"}"

# Where to send logs
: "${FORGES_LOG:="${TUNNEL_LOG:-"2"}"}"

: "${FORGES_PREFIX:="${TUNNEL_PREFIX:-"/usr/local"}"}"

: "${FORGES_USER:=""}"

# GitHub user to fetch keys from
: "${FORGES_GITHUB_USER:="${TUNNEL_GITHUB_USER:-""}"}"

# Environment file to load for reading defaults from.
: "${FORGES_DEFAULTS:="${FORGES_ROOTDIR}/../${CODER_BIN}.env"}"


log_init FORGES

# Load defaults
[ -n "$FORGES_DEFAULTS" ] && read_envfile "$FORGES_DEFAULTS" FORGES


ensure_ownership() {
  [ -z "${1:-}" ] && error "ensure_ownership: no path given"
  if [ "$(stat -c "%u" "$1")" != "$(id -u)" ]; then
    as_root chown "$(id -u)" "$1"
    verbose "Changed ownership of %s to %s" "$1" "$(id -un)"
  fi
}

sshkey2sha256() {
  ssh-keygen -l -f "$1" |
    grep -F "$2" |
    awk '{print $2}' |
    sed -E 's/^SHA256://g'
}

json2sha256() {
  jq ."ssh_key_fingerprints" "$1" |
    grep -F "$2" |
    awk '{print $2}'|
    sed -E -e 's/^"//g' -e 's/",?//g'
}


authorize_github() {
  # Download fingerprints reported by GH API
  _fingerprints=$(mktemp json.XXXXXX)
  download https://api.github.com/meta "$_fingerprints"

  for _domain in github.com gist.github.com; do
    verbose "Adding %s keys to %s" "$_domain" "${HOME}/.ssh/known_hosts"
    _gh_keys=$(mktemp known_hosts.XXXXXX)
    ssh-keyscan "$_domain" | grep -vE -e '^#' -e '^\s+$' > "$_gh_keys"
    for _crypto in RSA ECDSA ED25519; do
      if grep -F "$_domain" "${HOME}/.ssh/known_hosts" | grep -qF "$(to_lower "${_crypto}")" ; then
        debug "%s %s key already in %s" "$_domain" "${_crypto}" "${HOME}/.ssh/known_hosts"
      else
        verbose "Adding %s %s key to %s" "$_domain" "${_crypto}" "${HOME}/.ssh/known_hosts"
        # Compute the fingerprint of the key, see https://serverfault.com/a/701637
        _reported=$(sshkey2sha256 "$_gh_keys" "$_crypto")
        trace "sha256 sum as reported by the live server is: %s" "$_reported"
        # Extract the official fingerprint from the GitHub API. See
        # https://serverfault.com/a/701637
        _official=$(json2sha256 "$_fingerprints" "$_crypto")
        trace "GitHub's API reports sha256 sum should be: %s" "$_official"
        # If they match, add the key to the known_hosts file
        if [ "$_reported" = "$_official" ]; then
          grep -F "$(to_lower "${_crypto}")" "$_gh_keys" >> "${HOME}/.ssh/known_hosts"
        else
          warn "Fingerprint for %s key does not match official fingerprint" "${_crypto}"
        fi
      fi
    done
    rm -f "$_gh_keys"
  done
  rm -f "$_fingerprints"
}


if ! [ -d "${HOME}/.ssh" ]; then
  mkdir -p "${HOME}/.ssh"
  chmod go-rwx "${HOME}/.ssh"
  verbose "Created SSH directory in %s" "${HOME}/.ssh"
fi
# ensure_ownership "${HOME}/.ssh"

if ! [ -f "${HOME}/.ssh/known_hosts" ]; then
  touch "${HOME}/.ssh/known_hosts"
  chmod go-rwx "${HOME}/.ssh/known_hosts"
  verbose "Created SSH known_hosts file in %s" "${HOME}/.ssh/known_hosts"
fi
# ensure_ownership "${HOME}/.ssh/known_hosts"

authorize_github
