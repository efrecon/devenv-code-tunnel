#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
TUNNEL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common system; do
  for d in ../lib lib; do
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


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="cloudflare tunnel starter"

# Initialize
log_init TUNNEL

sshd_wait() {
  verbose "Wait for sshd to start..."
  while ! nc -z localhost "$TUNNEL_SSH"; do
    sleep 1
  done
}

tunnel_start() (
  # Remove all TUNNEL_ variables from the environment, since cloudflared
  # respects some of them and we force settings through the command line.
  ssh_port="$TUNNEL_SSH"
  unset_varset TUNNEL

  verbose "Starting cloudflare tunnel using %s, logging at %s" "$1" "$CLOUDFLARE_LOG"
  "$1" tunnel --no-autoupdate --url "tcp://localhost:$ssh_port" > "$CLOUDFLARE_LOG" 2>&1 &
)

tunnel_wait() {
  verbose "Wait for cloudflare tunnel to start..."
  url=$(while ! grep -o 'https://.*\.trycloudflare.com' "$CLOUDFLARE_LOG"; do sleep 1; done)
  public_key=$(cut -d' ' -f1,2 < "${TUNNEL_PREFIX}/etc/ssh_host_rsa_key.pub")
  verbose "Cloudflare tunnel started at %s" "$url"

  # TODO: Use regular logging instead?
  printf \\n
  printf \\n
  printf "Run the following command to connect:\n"
  printf "    ssh-keygen -R %s && echo '%s %s' >> ~/.ssh/known_hosts && ssh -o ProxyCommand='cloudflared access tcp --hostname %s' %s@%s\n" \
          "$TUNNEL_HOSTNAME" "$TUNNEL_HOSTNAME" "$public_key" "$url" "$(id -un)" "$TUNNEL_HOSTNAME"
  printf \\n
  printf "Run the following command to connect without verification (DANGER!):"
  printf "    ssh -o ProxyCommand='cloudflared access tcp --hostname %s' -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new %s@%s\n" \
          "$url" "$(id -un)" "$TUNNEL_HOSTNAME"
  printf \\n
  printf \\n
}


TUNNEL_HOSTNAME=$TUNNEL_NAME
[ -z "$TUNNEL_HOSTNAME" ] && TUNNEL_HOSTNAME=$(hostname)

CLOUDFLARE_LOG="${TUNNEL_PREFIX}/log/cloudflared.log"
CLOUDFLARE_BIN=$(find_inpath cloudflared "$TUNNEL_USER_PREFIX" "$TUNNEL_PREFIX")
if [ -n "$TUNNEL_SSH" ] && [ -n "$CLOUDFLARE_BIN" ]; then
  check_command nc || error "nc is not installed. Please install it first."
  sshd_wait
  tunnel_start "$CLOUDFLARE_BIN"
  tunnel_wait
fi
