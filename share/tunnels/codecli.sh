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
: "${TUNNEL_REEXPOSE:="code"}"


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


# Check if currently logged in as per the token present on disk.
tunnel_logged_in() {
  if [ -f "${TUNNEL_STORAGE%/}/token.json" ]; then
    token=$(cat "${TUNNEL_STORAGE%/}/token.json")
    if [ "$token" != "null" ]; then
      return 0
    fi
  fi
  return 1
}

# Wrapper around code tunnel. Will log automatically.
code_tunnel() { "$CODE_LWRAP" -- "$CODE_BIN" tunnel "$@"; }
code_tunnel_bg() {
  "$CODE_LWRAP" -- "$CODE_BIN" tunnel "$@" &
  CODE_PID=$!
}

# Wait for the message containing URL to grant access to tunnel to appear in the
# logs.
tunnel_grant() {
  # TODO: Rewrite with tail, since new access codes will be generated over time.
  verbose "$(wait_infile "$CODE_LOG" 'grant access.*use code')"
}


# Authorize device. This will print out a URL to the console. Open it in a
# browser and authorize the device.
tunnel_login() {
  # Whenever necessary: start a login at the provider, wait for the URL for
  # authorization to appear in the logs and reprint them. Then, wait for the
  # process to end: it will end once the link has been clicked and this device
  # authorized.
  verbose "Logging in at %s" "$TUNNEL_PROVIDER"

  # Start reprinting the logs, remember the PID of that process.
  "$CODE_LOGGER" -s "$CODER_BIN" -- "$CODE_LOG" &
  CODE_LOGGER_PID=$!

  # Login at the provider in the background and wait for the process to end.
  code_tunnel_bg user login --provider "$TUNNEL_PROVIDER"
  wait "$CODE_PID"

  # Kill the log re-printer tree, we might have children and signals might not
  # be propagated. Note: we cannot kill the process group, as it would kill too
  # many processes and the - semantic isn't supported on busybox.
  verbose "Logged in at %s" "$TUNNEL_PROVIDER"
  kill_tree "$CODE_LOGGER_PID"
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
  # Wait for "ready" message in log and extract URL from it.
  debug "Wait for code tunnel to start..."
  url=$(wait_infile "$CODE_LOG" 'Open this link in your browser' 'F' | grep -oE 'https?://.*')

  # Log URL, also make sure it appears in the container output.
  verbose "Code tunnel started at %s" "$url"
  reprint "$TUNNEL_GIST_FILE" <<EOF

(vs)code tunnel running, access it from your browser at the following URL:
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

# Check dependencies
CODE_BIN=$(find_inpath code "$TUNNEL_USER_PREFIX" "$TUNNEL_PREFIX")
[ -z "$CODE_BIN" ] && exit; # Gentle warning, in case not installed on purpose
CODE_ORCHESTRATION_DIR=${TUNNEL_ROOTDIR}/../orchestration
CODE_LOGGER=${CODE_ORCHESTRATION_DIR}/logger.sh
CODE_LWRAP=${CODE_ORCHESTRATION_DIR}/lwrap.sh
[ -x "$CODE_LOGGER" ] || error "Cannot find logger.sh"
[ -x "$CODE_LWRAP" ] || error "Cannot find lwrap.sh"
CODE_LOG=$("$CODE_LWRAP" -L -- "$CODE_BIN")

# configure, login and start the tunnel if the vscode CLI is installed.
tunnel_configure
verbose "Starting code tunnel using %s, logs at %s" "$CODE_BIN" "$CODE_LOG"
if is_true "$TUNNEL_FORCE" || ! tunnel_logged_in; then 
  tunnel_login
fi
if [ -z "$TUNNEL_REEXPOSE" ] || printf %s\\n "$TUNNEL_REEXPOSE" | grep -qF 'code'; then
  verbose "Forwarding logs from %s" "$CODE_LOG"
  "$CODE_LOGGER" -s "$CODE_BIN" -- "$CODE_LOG" &
fi
tunnel_start;  # Starts tunnel in the background
tunnel_wait
