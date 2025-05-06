#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
TUNNEL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common system; do
  for d in ../../lib ../lib lib; do
    if [ -d "${TUNNEL_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${TUNNEL_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done


# All following vars have defaults here, but will be set and inherited from
# the calling tunnel.sh script.
: "${TUNNEL_VERBOSE:=0}"
: "${TUNNEL_LOG:=2}"
: "${TUNNEL_NAME:=""}"
: "${TUNNEL_PREFIX:="/usr/local"}"
: "${TUNNEL_USER_PREFIX:="${HOME}/.local"}"
: "${TUNNEL_SSH:="2222"}"
: "${TUNNEL_GITHUB_USER:=""}"
: "${TUNNEL_REEXPOSE:="cloudflared"}"
: "${TUNNEL_GIST_FILE:=""}"


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="cloudflare tunnel starter"

# Initialize
log_init TUNNEL


sshd_wait() {
  debug "Wait for sshd to start..."
  while ! nc -z localhost "$TUNNEL_SSH"; do
    sleep 1
    trace "Waiting for sshd to start on port %s..." "$TUNNEL_SSH"
  done
  if [ -z "$TUNNEL_REEXPOSE" ] || printf %s\\n "$TUNNEL_REEXPOSE" | grep -qF 'sshd'; then
    verbose "sshd responding on port %s, forwarding logs from %s" "$TUNNEL_SSH" "${TUNNEL_PREFIX}/log/sshd.log"
    "$CLOUDFLARE_LOGGER" -s "sshd" -- "${TUNNEL_PREFIX}/log/sshd.log" &
  else
    verbose "sshd responding on port %s" "$TUNNEL_SSH"
  fi
}


tunnel_start() (
  # Remove all TUNNEL_ variables from the environment, since cloudflared
  # respects some of them and we force settings through the command line.
  ssh_port="$TUNNEL_SSH"
  unset_varset TUNNEL

  "$CLOUDFLARE_LWRAP" -- \
    "$CLOUDFLARE_BIN" tunnel \
      --no-autoupdate \
      --url "tcp://localhost:$ssh_port" &
)


tunnel_wait() {
  debug "Wait for cloudflare tunnel to start..."
  url=$(while ! grep -o 'https://.*\.trycloudflare.com' "$CLOUDFLARE_LOG"; do sleep 1; done)
  keyfile=$(find -type f -maxdepth 1 -name 'ssh_host_*_key.pub' "${TUNNEL_PREFIX}/etc" | head -n 1)
  public_key=$(cut -d' ' -f1,2 < "$keyfile")
  verbose "Cloudflare tunnel started at %s" "$url"

  reprint "$TUNNEL_GIST_FILE" <<EOF

cloudflare tunnel running, run the following command to connect securly:
    ssh-keygen -R $TUNNEL_HOSTNAME && echo '$TUNNEL_HOSTNAME $public_key' >> ~/.ssh/known_hosts && ssh -o ProxyCommand='cloudflared access tcp --hostname $url' $(id -un)@$TUNNEL_HOSTNAME

cloudflare tunnel running, run the following command to connect without verification (DANGER!):
    ssh -o ProxyCommand='cloudflared access tcp --hostname $url' -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new $(id -un)@$TUNNEL_HOSTNAME

EOF
}


TUNNEL_HOSTNAME=$TUNNEL_NAME
[ -z "$TUNNEL_HOSTNAME" ] && TUNNEL_HOSTNAME=$(hostname)

# Check dependencies
[ -z "$TUNNEL_SSH" ] && error "No ssh port provided"
CLOUDFLARE_BIN=$(find_inpath cloudflared "$TUNNEL_USER_PREFIX" "$TUNNEL_PREFIX")
[ -z "$CLOUDFLARE_BIN" ] && exit; # Gentle warning, in case not installed on purpose
CLOUDFLARE_ORCHESTRATION_DIR=${TUNNEL_ROOTDIR}/../orchestration
CLOUDFLARE_LOGGER=${CLOUDFLARE_ORCHESTRATION_DIR}/logger.sh
CLOUDFLARE_LWRAP=${CLOUDFLARE_ORCHESTRATION_DIR}/lwrap.sh
[ -x "$CLOUDFLARE_LOGGER" ] || error "Cannot find logger.sh"
[ -x "$CLOUDFLARE_LWRAP" ] || error "Cannot find lwrap.sh"
CLOUDFLARE_LOG=$("$CLOUDFLARE_LWRAP" -L -- "$CLOUDFLARE_BIN")

check_command nc || error "nc is not installed. Please install it first."
sshd_wait

verbose "Starting cloudflare tunnel using %s, logs at %s" "$CLOUDFLARE_BIN" "$CLOUDFLARE_LOG"
if [ -z "$TUNNEL_REEXPOSE" ] || printf %s\\n "$TUNNEL_REEXPOSE" | grep -qF 'cloudflared'; then
  verbose "Forwarding logs from %s" "$CODCLOUDFLARE_LOGE_LOG"
  "$CLOUDFLARE_LOGGER" -s "$CLOUDFLARE_BIN" -- "$CLOUDFLARE_LOG" &
fi
tunnel_start;  # Starts tunnel in the background
tunnel_wait
