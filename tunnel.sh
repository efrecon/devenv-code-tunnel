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


# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at TUNNEL_LOG.
: "${TUNNEL_VERBOSE:=0}"

# Where to send logs
: "${TUNNEL_LOG:=2}"

# Where to store tunnel data
: "${TUNNEL_STORAGE:="${HOME}/.vscode-tunnel"}"

# Default tunnel provider
: "${TUNNEL_PROVIDER:="github"}"

# Name of the tunnel, when empty the hostname will be used if it was set to
# something sensible, i.e. not the shortname of the container ID. Each time the
# name changes, you will have to reauthorize the tunnel with -f
: "${TUNNEL_NAME:=""}"

# Hook to run before starting the tunnel. This is useful for setting up
# environment variables or running commands that need to be run before the
# tunnel starts. The hook is run as the tunnel user.
: "${TUNNEL_HOOK:=""}"

# Force reauthorization of the device
: "${TUNNEL_FORCE:="0"}"

# Prefixes where things are installed.
: "${TUNNEL_PREFIX:="/usr/local"}"
: "${TUNNEL_USER_PREFIX:="${HOME}/.local"}"

# Alias for the home user
: "${TUNNEL_ALIAS:=}"

# Port of the SSH daemon to tunnel via cloudflare
: "${TUNNEL_SSH:="2222"}"

# Github user to fetch keys from
: "${TUNNEL_GITHUB_USER:=""}"


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="tunnel starter"
while getopts "a:fg:k:l:n:p:s:vh" opt; do
  case "$opt" in
    a) # Alias for the home user
      TUNNEL_ALIAS="$OPTARG";;
    f) # Force device authorization again
      TUNNEL_FORCE="1";;
    g) # GitHub user to fetch keys from and restrict ssh access to
      TUNNEL_GITHUB_USER="$OPTARG";;
    k) # Internet hook to run before starting the tunnel
      TUNNEL_HOOK="$OPTARG";;
    l) # Where to send logs
      TUNNEL_LOG="$OPTARG";;
    n) # Name of the tunnel, empty for random name
      TUNNEL_NAME="$OPTARG";;
    p) # Tunnel provider
      TUNNEL_PROVIDER="$OPTARG";;
    s) # Port of the SSH daemon, to tunnel via cloudflare
      TUNNEL_SSH="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      TUNNEL_VERBOSE=$((TUNNEL_VERBOSE + 1));;
    h) # Show help
      usage 0 TUNNEL
      ;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done

# Initialize
log_init TUNNEL

VSCODE_CLI_DATA_DIR=$TUNNEL_STORAGE
export VSCODE_CLI_DATA_DIR

# Arrange for a link to exists, pointing to the real home of the user. Make this
# the new home as much as possible.
alias_create() {
  AHOME=$(dirname "$HOME")/$1
  if ! [ -d "$AHOME" ]; then
    as_root ln -sf "$HOME" "$AHOME"
    as_root sed -ibak -E -e "s|${HOME}|${AHOME}|g" "/etc/passwd"
    TUNNEL_USER_PREFIX=$(printf %s\\n "$TUNNEL_USER_PREFIX" | sed -E "s|${HOME}|${AHOME}|g")
    HOME=$AHOME
    export HOME
  fi
}


code_tunnel_logged_in() {
  if [ -f "${TUNNEL_STORAGE%/}/token.json" ]; then
    token=$(cat "${TUNNEL_STORAGE%/}/token.json")
    if [ "$token" != "null" ]; then
      return 0
    fi
  fi
  return 1
}


code_tunnel_configure() {
  # Check if the tunnel provider is set and valid.
  if [ -z "$TUNNEL_PROVIDER" ]; then
    error "No tunnel provider specified. Please set TUNNEL_PROVIDER to github or azure."
  fi
  if [ "$TUNNEL_PROVIDER" != "github" ] && [ "$TUNNEL_PROVIDER" != "azure" ]; then
    error "Invalid tunnel provider specified. Please set TUNNEL_PROVIDER to github or azure."
  fi

  # Pick a name, from hostname or at random
  if [ -z "$TUNNEL_NAME" ]; then
    # If the hostname is not a random name, use it as the tunnel name.
    if ! hostname | grep -qE '[a-f0-9]{12}'; then
      TUNNEL_NAME=$(hostname)
    else
      TUNNEL_NAME=$(generate_random)
    fi
  elif [ "$TUNNEL_NAME" = "-" ]; then
    TUNNEL_NAME=
  else
    # If the hostname is generated, override it with the tunnel name if possible.
    # This will only work if the container was run with --privileged.
    if hostname | grep -qE '[a-f0-9]{12}'; then
      as_root hostname "$TUNNEL_NAME" ||
        warn "Using a generated hostname: %s. Force hostname of container to avoid having to re-authorize the device!" "$(hostname)"
    fi
  fi
}


# Authorize device. This will print out a URL to the console. Open it in a
# browser and authorize the device.
code_tunnel_login() {
  if is_true "$TUNNEL_FORCE"; then
    "$1" tunnel user login --provider "$TUNNEL_PROVIDER"
  elif ! code_tunnel_logged_in; then
    "$1" tunnel user login --provider "$TUNNEL_PROVIDER"
  fi
}

# Start the tunnel
code_tunnel_start() {
  if [ -z "$TUNNEL_NAME" ]; then
    "$1" tunnel --accept-server-license-terms --random-name
  else
    "$1" tunnel --accept-server-license-terms --name "$TUNNEL_NAME"
  fi
}


cloudflare_tunnel_start() {
  verbose "Starting cloudflare tunnel, logging at %s" "$TUNNEL_LOG"
  CLOUDFLARE_LOG="${TUNNEL_PREFIX}/log/cloudflared.log"
  "$1" tunnel --url "tcp://localhost:$TUNNEL_SSH" > "$CLOUDFLARE_LOG" 2>&1 &
  verbose "Wait for cloudflare tunnel to start..."
  url=$(while ! grep -o 'https://.*\.trycloudflare.com' "$CLOUDFLARE_LOG"; do sleep 1; done)
  public_key=$(cut -d' ' -f1,2 < "${TUNNEL_PREFIX}/etc/ssh/ssh_host_rsa_key.pub")
  verbose "Cloudflare tunnel started at %s" "$url"

  KNOWN_HOST=$TUNNEL_NAME
  [ -z "$KNOWN_HOST" ] && KNOWN_HOST=$(hostname)

  printf \\n
  printf \\n
  printf "Run the following command to connect:\n"
  printf "    ssh-keygen -R %s && echo '%s %s' >> ~/.ssh/known_hosts && ssh -o ProxyCommand='cloudflared access tcp --hostname %s' %s@%s\n" \
          "$KNOWN_HOST" "$KNOWN_HOST" "$public_key" "$url" "$(id -un)" "$KNOWN_HOST"
  printf \\n
  printf "Run the following command to connect without verification (DANGER!):"
  printf "    ssh -o ProxyCommand='cloudflared access tcp --hostname %s' -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new %s@%s\n" \
          "$url" "$(id -un)" "$KNOWN_HOST"
  printf \\n
  printf \\n
}


# Create the alias for the home user
[ -n "$TUNNEL_ALIAS" ] && alias_create "$TUNNEL_ALIAS"

# Start services
export_varset "TUNNEL"
if [ -x "${TUNNEL_ROOTDIR}/services.sh" ]; then
  verbose "Starting services"
  SERVICES_LOG=$TUNNEL_LOG \
  SERVICES_VERBOSE=$TUNNEL_VERBOSE \
  SERVICES_PREFIX=$TUNNEL_PREFIX \
    "${TUNNEL_ROOTDIR}/services.sh"
fi

# Start the Internet hook to perform extra setup
if [ -n "$TUNNEL_HOOK" ]; then
  verbose "Running hook: %s" "$TUNNEL_HOOK"
  internet_install "$TUNNEL_HOOK" hook ""
fi


CODE_BIN=$(find_inpath code "$TUNNEL_USER_PREFIX" "$TUNNEL_PREFIX")
if [ -n "$CODE_BIN" ]; then
  code_tunnel_configure
  code_tunnel_login "$CODE_BIN"
  code_tunnel_start "$CODE_BIN" &
fi

CLOUDFLARE_BIN=$(find_inpath cloudflared "$TUNNEL_USER_PREFIX" "$TUNNEL_PREFIX")
if [ -n "$TUNNEL_SSH" ] && [ -n "$CLOUDFLARE_BIN" ]; then
  cloudflare_tunnel_start "$CLOUDFLARE_BIN" &
fi
