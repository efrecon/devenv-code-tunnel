#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Absolute location of the script where this script is located.
TAILCAT_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common wait system delegate; do
  for d in ../../lib ../lib lib; do
    if [ -d "${TAILCAT_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${TAILCAT_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Arrange to set the CODER_BIN variable to the name of the script
bin_name


# All following vars have defaults here, but will be set and inherited from
# the calling tunnel.sh script.
: "${XDG_CONFIG_HOME:="${HOME}/.config"}"
: "${TAILCAT_VERBOSE:=${TUNNEL_VERBOSE:-0}}"
: "${TAILCAT_LOG:=${TUNNEL_LOG:-2}}"
: "${TAILCAT_HOSTNAME:="${TUNNEL_NAME:-""}"}"
: "${TAILCAT_PREFIX:="${TUNNEL_PREFIX:-"/usr/local"}"}"
: "${TAILCAT_USER_PREFIX:="${TUNNEL_USER_PREFIX:-"${HOME}/.local"}"}"
: "${TAILCAT_SSH:=${TUNNEL_SSH:-2222}}"
: "${TAILCAT_GITHUB_USER:="${TUNNEL_GITHUB_USER:-""}"}"
: "${TAILCAT_REEXPOSE:="${TUNNEL_REEXPOSE:-"tailcat"}"}"
: "${TAILCAT_GIST_FILE:="${TUNNEL_GIST_FILE:-""}"}"
: "${TAILCAT_CONFIG_DIR:="${XDG_CONFIG_HOME}/tailcat"}"
: "${TAILCAT_KEYS_DIR:="${TAILCAT_CONFIG_DIR}/keys"}"
# Environment file to load for reading defaults from.
: "${TAILCAT_DEFAULTS:="${TAILCAT_ROOTDIR}/../../etc/${CODER_BIN}.env"}"




sshd_wait() {
  trace "Wait for sshd to start..."
  while ! nc -z localhost "$TAILCAT_SSH"; do
    sleep 1
    trace "Waiting for sshd to start on port %s..." "$TAILCAT_SSH"
  done
  debug "sshd alive on port %s" "$TAILCAT_SSH"
}


tunnel_pubkey() {
  for _dir in "$TAILCAT_PREFIX"/etc "$TAILCAT_USER_PREFIX"/etc; do
    if [ -d "$_dir" ]; then
      keyfile=$(find "$_dir" -type f -maxdepth 1 -name 'ssh_host_*_key.pub' | head -n 1)
      if [ -n "$keyfile" ]; then
        cut -d' ' -f1,2 < "$keyfile"
        return 0
      fi
    fi
  done
}


tunnel_configure() {
  if [ ! -f "${TAILCAT_KEYS_DIR}/${TUNNEL_NAME}.private.json" ]; then
    verbose "Generating key for tunnel $TUNNEL_NAME"
    "$TAILCAT_BIN" genkey --key "$TUNNEL_NAME" > /dev/null
    if [ ! -f "${TAILCAT_KEYS_DIR}/${TUNNEL_NAME}.private.json" ]; then
      error "Failed to generate key for tunnel $TUNNEL_NAME"
    fi
  else
    trace "Key for tunnel $TUNNEL_NAME already configured"
  fi
}


tunnel_start() {
  spawn -n tailcat -- \
    "$TAILCAT_LWRAP" -- \
      "$TAILCAT_BIN" --key "$TUNNEL_NAME" serve "$TAILCAT_SSH" "$@" > /dev/null
}


tunnel_info() {
  public_key=$(tunnel_pubkey)
  verbose "tailcat tunnel started at %s" "$1"

  reprint "$TAILCAT_GIST_FILE" <<EOF

tailcat tunnel running, run the following command to connect securely:
    ssh-keygen -R $TAILCAT_HOSTNAME && echo '$TAILCAT_HOSTNAME $public_key' >> ~/.ssh/known_hosts && ssh -o ProxyCommand='tailcat $1 $TAILCAT_SSH' $(id -un)@$TAILCAT_HOSTNAME

tailcat tunnel running, run the following command to connect without verification (DANGER!):
    ssh -o ProxyCommand='tailcat $1 $TAILCAT_SSH' -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new $(id -un)@$TAILCAT_HOSTNAME

tailcat DANGEROUS configuration snippet for \$HOME/.ssh/config:

Host $TAILCAT_HOSTNAME
  HostName $TAILCAT_HOSTNAME
  ProxyCommand tailcat $1 $TAILCAT_SSH
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking accept-new
  User $(id -un)

EOF
  # Timestamp the gist file to indicate when it was last updated.
  [ -n "$TAILCAT_GIST_FILE" ] && "$TAILCAT_TIMESTAMP" -s 0 -- "$TAILCAT_GIST_FILE" || true
}


tunnel_wait() {
  debug "Wait for cloudflare tunnel to start..."
  addr=$(when_infile "$TAILCAT_LOG" 'E' \
          'tc[A-Za-z0-9_-]{30,250}' - | grep -oE 'tc[A-Za-z0-9_-]{30,250}')
  tunnel_info "$addr"
}


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="tailcat tunnel starter"

# Initialize
log_init TAILCAT

# Load defaults
[ -n "$TAILCAT_DEFAULTS" ] && read_envfile "$TAILCAT_DEFAULTS" TAILCAT


[ -z "$TAILCAT_HOSTNAME" ] && TAILCAT_HOSTNAME=$(hostname)

# Check dependencies
[ -z "$TAILCAT_SSH" ] && error "No ssh port provided"
TAILCAT_BIN=$(find_inpath tailcat "$TAILCAT_USER_PREFIX" "$TAILCAT_PREFIX")
[ -z "$TAILCAT_BIN" ] && exit; # Gentle warning, in case not installed on purpose
TAILCAT_ORCHESTRATION_DIR=${TAILCAT_ROOTDIR}/../orchestration
TAILCAT_LOGGER=${TAILCAT_ORCHESTRATION_DIR}/logger.sh
TAILCAT_LWRAP=${TAILCAT_ORCHESTRATION_DIR}/lwrap.sh
TAILCAT_TIMESTAMP=${TAILCAT_ORCHESTRATION_DIR}/timestamp.sh
[ -x "$TAILCAT_LOGGER" ] || error "Cannot find logger.sh"
[ -x "$TAILCAT_LWRAP" ] || error "Cannot find lwrap.sh"
[ -x "$TAILCAT_TIMESTAMP" ] || error "Cannot find timestamp.sh"
TAILCAT_LOG=$("$TAILCAT_LWRAP" -L -- "$TAILCAT_BIN")

check_command nc || error "nc is not installed. Please install it first."
sshd_wait
debug "TAILCAT_REEXPOSE is set to %s" "$TAILCAT_REEXPOSE"

tunnel_configure
debug "Starting tailcat tunnel using %s, logs at %s" "$TAILCAT_BIN" "$TAILCAT_LOG"
if [ -z "$TAILCAT_REEXPOSE" ] || printf %s\\n "$TAILCAT_REEXPOSE" | grep -qF 'tailcat'; then
  debug "Forwarding logs from %s" "$TAILCAT_LOG"
  spawn "$TAILCAT_LOGGER" -s "$TAILCAT_BIN" -- "$TAILCAT_LOG" >/dev/null
fi
tunnel_start "$@"
tunnel_wait

TAILCAT_PID=$(spawn_latest)
trace "Tailcat tunnel running as PID %d, waiting for it to exit.." "$TAILCAT_PID"
spawn_wait "$TAILCAT_PID"; # Wait for the tunnel to end.

_ret=$?
spawn_kill -t -r "cleanup"; # Kill the log relay, if any.
exit $_ret
