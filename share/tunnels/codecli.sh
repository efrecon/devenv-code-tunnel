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
: "${TUNNEL_STORAGE:="${HOME}/.vscode-tunnel"}"
: "${TUNNEL_PROVIDER:="github"}"
: "${TUNNEL_NAME:=""}"
: "${TUNNEL_HOOK:=""}"
: "${TUNNEL_FORCE:="0"}"
: "${TUNNEL_PREFIX:="/usr/local"}"
: "${TUNNEL_USER_PREFIX:="${HOME}/.local"}"
: "${TUNNEL_ALIAS:=}"
: "${TUNNEL_REEXPOSE:=""}"


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="vscode tunnel starter"

# Initialize
log_init TUNNEL

# Enforce storage location for vscode tunnel
VSCODE_CLI_DATA_DIR=$TUNNEL_STORAGE
export VSCODE_CLI_DATA_DIR


# Try using the name of the tunnel for the hostname, whenever relevant. This
# allows to reuse the tunnel in a new container, since the vscode tunnel CLI
# uses the hostname to detect if the device where the tunnel is running is the
# same.
tunnel_configure() {
  if [ -n "$TUNNEL_ORIGINAL_NAME" ] && [ -n "$TUNNEL_NAME" ]; then
    # If the hostname is generated, override it with the tunnel name if possible.
    # This will only work if the container was run with --privileged.
    if hostname | grep -qE '[a-f0-9]{12}'; then
      as_root hostname "$TUNNEL_NAME" ||
        warn "Using a generated hostname: %s. Force hostname of container to avoid having to re-authorize the device!" "$(hostname)"
    fi
  fi
}


tunnel_logged_in() {
  if [ -f "${TUNNEL_STORAGE%/}/token.json" ]; then
    token=$(cat "${TUNNEL_STORAGE%/}/token.json")
    if [ "$token" != "null" ]; then
      return 0
    fi
  fi
  return 1
}

# Wrapper around code tunnel
code_tunnel() { "${CODE_BIN:-code}" tunnel "$@" >>"$CODE_LOG" 2>&1; }
code_tunnel_bg() {
  "${CODE_BIN:-code}" tunnel "$@" >>"$CODE_LOG" 2>&1 &
}

# Authorize device. This will print out a URL to the console. Open it in a
# browser and authorize the device.
tunnel_login() {
  if is_true "$TUNNEL_FORCE"; then
    code_tunnel user login --provider "$TUNNEL_PROVIDER"
  elif ! tunnel_logged_in; then
    code_tunnel user login --provider "$TUNNEL_PROVIDER"
  fi
}

# Start the tunnel
tunnel_start() {
  if [ -z "$TUNNEL_NAME" ]; then
    code_tunnel_bg --accept-server-license-terms --random-name
  else
    code_tunnel_bg --accept-server-license-terms --name "$TUNNEL_NAME"
  fi
}

# Wait for the tunnel to be started and print out its URL
tunnel_wait() {
  debug "Wait for code tunnel to start..."
  _started=$(while ! grep -F 'Open this link in your browser' "$CODE_LOG"; do sleep 1; done)
  url=$(printf %s\\n "$_started" | grep -oE 'https?://.*')

  verbose "Code tunnel started at %s" "$url"

  while IFS= read -r line; do
    _log "" "$line"
    if [ -n "$TUNNEL_GIST_FILE" ]; then
      printf %s\\n "$line" >>"$TUNNEL_GIST_FILE"
    fi
  done <<EOF

Code tunnel running, access it from your browser at the following URL:
    $url

EOF
}

# Check if the tunnel provider is set and valid.
if [ -z "$TUNNEL_PROVIDER" ]; then
  error "No tunnel provider specified. Please set TUNNEL_PROVIDER to github or azure."
fi
if [ "$TUNNEL_PROVIDER" != "github" ] && [ "$TUNNEL_PROVIDER" != "azure" ]; then
  error "Invalid tunnel provider specified. Please set TUNNEL_PROVIDER to github or azure."
fi


# configure, login and start the tunnel if the vscode CLI is installed.
CODE_BIN=$(find_inpath code "$TUNNEL_USER_PREFIX" "$TUNNEL_PREFIX")
CODE_LOG="${TUNNEL_PREFIX}/log/code.log"
if [ -n "$CODE_BIN" ]; then
  tunnel_configure
  verbose "Starting code tunnel using %s, logs at %s" "$CODE_BIN" "$CODE_LOG"
  if [ -z "$TUNNEL_REEXPOSE" ] || printf %s\\n "$TUNNEL_REEXPOSE" | grep -qF 'code'; then
    verbose "Forwarding logs from %s" "$CODE_LOG"
    "$TUNNEL_ROOTDIR/../orchestration/logger.sh" -s "$CODE_BIN" -- "$CODE_LOG" &
  fi
  tunnel_login
  tunnel_start;  # Starts tunnel in the background
  tunnel_wait
fi
