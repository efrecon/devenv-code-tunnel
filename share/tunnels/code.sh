#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
CODE_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common wait system delegate; do
  for d in ../../lib ../lib lib; do
    if [ -d "${CODE_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${CODE_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Arrange to set the CODER_BIN variable to the name of the script
bin_name


# All following vars have defaults here, but will be set and inherited from
# the calling tunnel.sh script.
: "${CODE_VERBOSE:=${TUNNEL_VERBOSE:-0}}"
: "${CODE_LOG:=${TUNNEL_LOG:-2}}"
: "${CODE_NAME:="${TUNNEL_NAME:-""}"}"
: "${CODE_PREFIX:="${TUNNEL_PREFIX:-"/usr/local"}"}"
: "${CODE_USER_PREFIX:="${TUNNEL_USER_PREFIX:-"${HOME}/.local"}"}"
: "${CODE_SSH:=${TUNNEL_SSH:-2222}}"
: "${CODE_GITHUB_USER:="${TUNNEL_GITHUB_USER:-""}"}"
: "${CODE_REEXPOSE:="${TUNNEL_REEXPOSE:-"code"}"}"
: "${CODE_GIST_FILE:="${TUNNEL_GIST_FILE:-""}"}"
: "${CODE_PROVIDER:="${TUNNEL_PROVIDER:-"github"}"}"
: "${CODE_FORCE:="${TUNNEL_FORCE:-"0"}"}"

: "${CODE_STORAGE:="${TUNNEL_CODE_STORAGE:-"${HOME}/.vscode-tunnel"}"}"
: "${CODE_ORIGINAL_NAME:="${TUNNEL_ORIGINAL_NAME:-""}"}"

# Number of seconds to wait before restarting tunnel when starting did not work.
# Set to negative to disable.
: "${CODE_RESTART:="${TUNNEL_CODE_RESTART:-5}"}"
# Environment file to load for reading defaults from.
: "${CODE_DEFAULTS:="${CODE_ROOTDIR}/../../etc/${CODER_BIN}.env"}"


# Try using the name of the tunnel for the hostname, whenever relevant. This
# allows to reuse the tunnel in a new container, since the vscode tunnel CLI
# uses the hostname to detect if the device where the tunnel is running is the
# same.
tunnel_configure() {
  if [ -n "$CODE_ORIGINAL_NAME" ] && [ -n "$CODE_NAME" ]; then
    # If the hostname is generated, override it with the tunnel name if possible.
    # This will only work if the container was run with --privileged.
    if hostname | grep -qE '[a-f0-9]{12}'; then
      as_root hostname "$CODE_NAME" ||
        warn "Using a generated hostname: %s. Force hostname of container to avoid having to re-authorize the device!" "$(hostname)"
    fi
  fi
}


# Check if currently logged in as per the token present on disk.
tunnel_logged_in() {
  if [ -f "${CODE_STORAGE%/}/token.json" ]; then
    token=$(cat "${CODE_STORAGE%/}/token.json")
    if [ "$token" != "null" ]; then
      return 0
    fi
  fi
  return 1
}

# Wrapper around code tunnel. Will log automatically.
code_tunnel() { "$CODE_LWRAP" -- "$CODE_BIN" tunnel "$@"; }
code_tunnel_bg() {
  spawn "$CODE_LWRAP" -- "$CODE_BIN" tunnel "$@"
}


# Authorize device. This will print out a URL to the console. Open it in a
# browser and authorize the device.
tunnel_login() {
  # Whenever necessary: start a login at the provider, wait for the URL for
  # authorization to appear in the logs and reprint them. Then, wait for the
  # process to end: it will end once the link has been clicked and this device
  # authorized.
  debug "Logging in at %s" "$CODE_PROVIDER"

  # Start reprinting the logs, remember the PID of that process.
  spawn "$CODE_LOGGER" -s "$CODER_BIN" -- "$CODE_LOG"

  # Login at the provider in the background and wait for the process to end.
  code_tunnel_bg user login --provider "$CODE_PROVIDER"
  spawn_wait "$(spawn_latest)"

  # Kill the log re-printer tree, we might have children and signals might not
  # be propagated. Note: we cannot kill the process group, as it would kill too
  # many processes and the - semantic isn't supported on busybox.
  verbose "Logged in at %s" "$CODE_PROVIDER"
  spawn_kill -t -r "login cleanup" # Kill all spawned processes, including the logger
}


# Start the tunnel
tunnel_start() {
  if [ -z "$CODE_NAME" ]; then
    code_tunnel_bg --accept-server-license-terms --random-name "$@"
  else
    code_tunnel_bg --accept-server-license-terms --name "$CODE_NAME" "$@"
  fi
}


# Kill the current tunnel and set the restart flag; returns 0 to stop when_infile
# so the parent loop can call tunnel_start and capture the new PID.
tunnel_restart() {
  warn "Error in tunnel: $1"
  CODE_PID=$(spawn_latest)
  [ -n "$CODE_PID" ] && spawn_kill -t -r "restart" "$CODE_PID"
  touch "$_CODE_RESTART_FLAG"
  return 0
}


tunnel_info() {
  # Log URL, also make sure it appears in the container output.
  verbose "Code tunnel started at %s" "$1"
  reprint "$CODE_GIST_FILE" <<EOF

(vs)code tunnel running, access it from your browser at the following URL:
    $1

EOF
  # Timestamp the gist file to indicate when it was last updated.
  "$CODE_TIMESTAMP" -s 0 -- "$CODE_GIST_FILE"
}


# Wait for the tunnel to be started and print out its URL
tunnel_wait() {
  # _CODE_RESTART_FLAG is inherited by the when_infile subshell so tunnel_restart
  # can signal back without modifying _CODER_PIDS in the child.
  _CODE_RESTART_FLAG=$(mktemp "${TMPDIR:-/tmp}/restart.XXXXXX")
  debug "Wait for code tunnel to start..."
  while true; do
    url=$(when_infile "$CODE_LOG" 'E' \
            'error connecting to tunnel:' tunnel_restart \
            '(Open this link in your browser|➜\s+Open:)' - | grep -oE 'https?://.*') || true
    if [ -f "$_CODE_RESTART_FLAG" ]; then
      rm -f "$_CODE_RESTART_FLAG"
      [ "$CODE_RESTART" -lt 0 ] && break
      sleep "$CODE_RESTART"
      tunnel_start
      continue
    fi
    break
  done
  [ -n "$CODE_GIST_FILE" ] && tunnel_info "$url"
}


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="vscode tunnel starter"

# Initialize
log_init TUNNEL

# Load defaults
[ -n "$CODE_DEFAULTS" ] && read_envfile "$CODE_DEFAULTS" CODE


# Enforce storage location for vscode tunnel
VSCODE_CLI_DATA_DIR=$CODE_STORAGE
export VSCODE_CLI_DATA_DIR


# Check if the tunnel provider is set and valid.
if [ -z "$CODE_PROVIDER" ]; then
  error "No tunnel provider specified. Please set TUNNEL_PROVIDER to github or azure."
fi
if [ "$CODE_PROVIDER" != "github" ] && [ "$CODE_PROVIDER" != "azure" ]; then
  error "Invalid tunnel provider specified. Please set TUNNEL_PROVIDER to github or azure."
fi

# Check dependencies
CODE_BIN=$(find_inpath code "$CODE_USER_PREFIX" "$CODE_PREFIX")
[ -z "$CODE_BIN" ] && exit; # Gentle warning, in case not installed on purpose
CODE_ORCHESTRATION_DIR=${CODE_ROOTDIR}/../orchestration
CODE_LOGGER=${CODE_ORCHESTRATION_DIR}/logger.sh
CODE_LWRAP=${CODE_ORCHESTRATION_DIR}/lwrap.sh
CODE_TIMESTAMP=${CODE_ORCHESTRATION_DIR}/timestamp.sh
[ -x "$CODE_LOGGER" ] || error "Cannot find logger.sh"
[ -x "$CODE_LWRAP" ] || error "Cannot find lwrap.sh"
[ -x "$CODE_TIMESTAMP" ] || error "Cannot find timestamp.sh"
CODE_LOG=$("$CODE_LWRAP" -L -- "$CODE_BIN")

# configure, login and start the tunnel if the vscode CLI is installed.
debug "Starting code tunnel using %s, logs at %s" "$CODE_BIN" "$CODE_LOG"
tunnel_configure
if is_true "$CODE_FORCE" || ! tunnel_logged_in; then
  tunnel_login
fi
if [ -z "$CODE_REEXPOSE" ] || printf %s\\n "$CODE_REEXPOSE" | grep -qF 'code'; then
  debug "Forwarding logs from %s" "$CODE_LOG"
  spawn "$CODE_LOGGER" -s "$CODE_BIN" -- "$CODE_LOG"
fi
tunnel_start "$@"
tunnel_wait

CODE_PID=$(spawn_latest)
trace "Code tunnel running as PID %d, waiting for it to exit.." "$CODE_PID"
spawn_wait "$CODE_PID"; # Wait for the tunnel to end.

_ret=$?
spawn_kill -t -r "cleanup"; # Kill the log relay, if any.
exit $_ret
