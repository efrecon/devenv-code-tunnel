#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
CLOUDFLARE_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common wait system; do
  for d in ../../lib ../lib lib; do
    if [ -d "${CLOUDFLARE_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${CLOUDFLARE_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Arrange to set the CODER_BIN variable to the name of the script
bin_name


# All following vars have defaults here, but will be set and inherited from
# the calling tunnel.sh script.
: "${CLOUDFLARE_VERBOSE:=${TUNNEL_VERBOSE:-0}}"
: "${CLOUDFLARE_LOG:=${TUNNEL_LOG:-2}}"
: "${CLOUDFLARE_HOSTNAME:="${TUNNEL_NAME:-""}"}"
: "${CLOUDFLARE_PREFIX:="${TUNNEL_PREFIX:-"/usr/local"}"}"
: "${CLOUDFLARE_USER_PREFIX:="${TUNNEL_USER_PREFIX:-"${HOME}/.local"}"}"
: "${CLOUDFLARE_SSH:=${TUNNEL_SSH:-2222}}"
: "${CLOUDFLARE_GITHUB_USER:="${TUNNEL_GITHUB_USER:-""}"}"
: "${CLOUDFLARE_REEXPOSE:="${TUNNEL_REEXPOSE:-"cloudflared"}"}"
: "${CLOUDFLARE_GIST_FILE:="${TUNNEL_GIST_FILE:-""}"}"
# Protocol to use for the cloudflare tunnel. Force http2 when using krun, since
# krun has problems with http3/quic.
: "${CLOUDFLARE_PROTOCOL:="${TUNNEL_CLOUDFLARE_PROTOCOL:-"auto"}"}"
# Environment file to load for reading defaults from.
: "${CLOUDFLARE_DEFAULTS:="${CLOUDFLARE_ROOTDIR}/../../etc/${CODER_BIN}.env"}"




sshd_wait() {
  trace "Wait for sshd to start..."
  while ! nc -z localhost "$CLOUDFLARE_SSH"; do
    sleep 1
    trace "Waiting for sshd to start on port %s..." "$CLOUDFLARE_SSH"
  done
}


tunnel_pubkey() {
  for _dir in "$CLOUDFLARE_PREFIX"/etc "$CLOUDFLARE_USER_PREFIX"/etc; do
    if [ -d "$_dir" ]; then
      keyfile=$(find "$_dir" -type f -maxdepth 1 -name 'ssh_host_*_key.pub' | head -n 1)
      if [ -n "$keyfile" ]; then
        cut -d' ' -f1,2 < "$keyfile"
        return 0
      fi
    fi
  done
}


tunnel_start() (
  # Remove all TUNNEL_ variables from the environment, since cloudflared
  # respects some of them and we force settings through the command line. Pass
  # all remaining arguments blindly to the command.
  unset_varset TUNNEL

  "$CLOUDFLARE_LWRAP" -- \
    "$CLOUDFLARE_BIN" tunnel \
      --no-autoupdate \
      --protocol "${CLOUDFLARE_PROTOCOL}" \
      --url "tcp://localhost:$CLOUDFLARE_SSH" \
      "$@" &
)


tunnel_info() {
  url=$(printf %s\\n "$1" | grep -oE 'https://.*\.trycloudflare.com')
  public_key=$(tunnel_pubkey)
  verbose "Cloudflare tunnel started at %s" "$url"

  reprint "$CLOUDFLARE_GIST_FILE" <<EOF

cloudflare tunnel running, run the following command to connect securely:
    ssh-keygen -R $CLOUDFLARE_HOSTNAME && echo '$CLOUDFLARE_HOSTNAME $public_key' >> ~/.ssh/known_hosts && ssh -o ProxyCommand='cloudflared access tcp --hostname $url' $(id -un)@$CLOUDFLARE_HOSTNAME

cloudflare tunnel running, run the following command to connect without verification (DANGER!):
    ssh -o ProxyCommand='cloudflared access tcp --hostname $url' -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new $(id -un)@$CLOUDFLARE_HOSTNAME

DANGEROUS configuration snippet for \$HOME/.ssh/config:

Host $CLOUDFLARE_HOSTNAME
  HostName $CLOUDFLARE_HOSTNAME
  ProxyCommand cloudflared access tcp --hostname $url
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking accept-new
  User $(id -un)

EOF

  return 1;  # Keep reading the file, as per convention for when_infile
}


tunnel_wait() {
  debug "Wait for cloudflare tunnels to start..."
  when_infile "$CLOUDFLARE_LOG" 'E' \
    'https://.*\.trycloudflare.com' tunnel_info
}


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="cloudflare tunnel starter"

# Initialize
log_init CLOUDFLARE

# Load defaults
[ -n "$CLOUDFLARE_DEFAULTS" ] && read_envfile "$CLOUDFLARE_DEFAULTS" CLOUDFLARE


[ -z "$CLOUDFLARE_HOSTNAME" ] && CLOUDFLARE_HOSTNAME=$(hostname)

# Check dependencies
[ -z "$CLOUDFLARE_SSH" ] && error "No ssh port provided"
CLOUDFLARE_BIN=$(find_inpath cloudflared "$CLOUDFLARE_USER_PREFIX" "$CLOUDFLARE_PREFIX")
[ -z "$CLOUDFLARE_BIN" ] && exit; # Gentle warning, in case not installed on purpose
CLOUDFLARE_ORCHESTRATION_DIR=${CLOUDFLARE_ROOTDIR}/../orchestration
CLOUDFLARE_LOGGER=${CLOUDFLARE_ORCHESTRATION_DIR}/logger.sh
CLOUDFLARE_LWRAP=${CLOUDFLARE_ORCHESTRATION_DIR}/lwrap.sh
[ -x "$CLOUDFLARE_LOGGER" ] || error "Cannot find logger.sh"
[ -x "$CLOUDFLARE_LWRAP" ] || error "Cannot find lwrap.sh"
CLOUDFLARE_LOG=$("$CLOUDFLARE_LWRAP" -L -- "$CLOUDFLARE_BIN")

check_command nc || error "nc is not installed. Please install it first."
sshd_wait

debug "Starting cloudflare tunnel using %s, logs at %s" "$CLOUDFLARE_BIN" "$CLOUDFLARE_LOG"
if [ -z "$CLOUDFLARE_REEXPOSE" ] || printf %s\\n "$CLOUDFLARE_REEXPOSE" | grep -qF 'cloudflared'; then
  debug "Forwarding logs from %s" "$CLOUDFLARE_LOG"
  "$CLOUDFLARE_LOGGER" -s "$CLOUDFLARE_BIN" -- "$CLOUDFLARE_LOG" &
fi
tunnel_start "$@";  # Starts tunnel in the background
tunnel_wait
