#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Absolute location of the script where this script is located.
CODE_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common wait system delegate; do
  for d in ../../lib ../lib lib; do
    if [ -d "${CODE_ROOTDIR}/$d" ] && [ -f "${CODE_ROOTDIR}/$d/${lib}.sh" ]; then
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
# Publish the device authorization code to the gist, when one is used. Anyone
# who can read the gist could use the code to authorize the device first.
: "${CODE_AUTH_PUBLISH:="${TUNNEL_CODE_AUTH_PUBLISH:-"1"}"}"

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

# Wrapper around code tunnel, in the background. Will log automatically.
# Records the log location and size in _SPAWN_LOG and _SPAWN_LOG_OFFSET.
code_tunnel_bg() {
  spawn_logged -n code "$CODE_LWRAP" -- "$CODE_BIN" tunnel "$@"
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

  # Login at the provider in the background.
  code_tunnel_bg user login --provider "$CODE_PROVIDER" >/dev/null
  _login_pid=$(spawn_latest)

  # Watch the logs of the login for the device authorization line and propagate
  # it to the gist (and container output). Runs in the background since the
  # login might end without ever printing it. The PID file allows to stop the
  # watcher (and its tail process) once login has ended.
  _CODE_AUTH_PIDFILE=$(mktemp_ext auth pid)
  (
    _WHEN_INFILE_PIDFILE=$_CODE_AUTH_PIDFILE
    when_infile "$_SPAWN_LOG_OFFSET" "$_SPAWN_LOG" 'E' \
      'use code [A-Za-z0-9-]+' tunnel_auth_info >/dev/null
  ) &
  _auth_watcher=$!

  # Wait for the login to end. Capture the exit code instead of letting set -e
  # abort, so the watcher is always stopped.
  _login_rc=0
  spawn_wait "$_login_pid" || _login_rc=$?
  when_infile_stop "$_CODE_AUTH_PIDFILE"
  wait "$_auth_watcher" 2>/dev/null || true
  rm -f "$_CODE_AUTH_PIDFILE"

  # Kill the log re-printer tree, we might have children and signals might not
  # be propagated. Note: we cannot kill the process group, as it would kill too
  # many processes and the - semantic isn't supported on busybox.
  spawn_kill -t -r "login cleanup" # Kill all spawned processes, including the logger
  [ "$_login_rc" -eq 0 ] || error "Login at $CODE_PROVIDER failed with exit code $_login_rc"
  verbose "Logged in at %s" "$CODE_PROVIDER"
}


# Start the tunnel. code_tunnel_bg records the log location and size, so
# tunnel_wait only considers lines from this run (and not from earlier runs or
# failed attempts).
tunnel_start() {
  if [ -z "$CODE_NAME" ]; then
    code_tunnel_bg --accept-server-license-terms --random-name "$@" >/dev/null
  else
    code_tunnel_bg --accept-server-license-terms --name "$CODE_NAME" "$@" >/dev/null
  fi
}


# Kill the current tunnel and set the restart flag; returns 0 to stop when_infile
# so the parent loop can call tunnel_start and capture the new PID.
# shellcheck disable=SC2329 # Called by when_infile
tunnel_restart() {
  warn "Error in tunnel: $1"
  CODE_PID=$(spawn_latest)
  [ -n "$CODE_PID" ] && spawn_kill -t -r "restart" "$CODE_PID"
  touch "$_CODE_RESTART_FLAG"
  return 0
}


# Print out the device authorization details found in the log line passed as an
# argument, also to the gist file. Returns 0 so when_infile stops watching.
# shellcheck disable=SC2329 # Called by when_infile
tunnel_auth_info() {
  _auth_url=$(printf %s\\n "$1" | grep -oE 'https?://[^ ]+' | head -n 1)
  _auth_code=$(printf %s\\n "$1" | grep -oE 'use code [A-Za-z0-9-]+' | sed -E 's/^use code //')
  verbose "Device authorization required at %s with code %s" "$_auth_url" "$_auth_code"

  # Anyone able to read the gist could use the code to authorize the device
  # with their own account. Allow to only print it to the container output.
  _auth_gist=$CODE_GIST_FILE
  if ! is_true "$CODE_AUTH_PUBLISH"; then
    [ -n "$_auth_gist" ] && debug "Not publishing device authorization code to gist"
    _auth_gist=
  fi
  gist_publish "$_auth_gist" "$CODE_TIMESTAMP" <<EOF

(vs)code tunnel requires device authorization at $CODE_PROVIDER. Open:
    $_auth_url
and enter the code:
    $_auth_code

EOF
  return 0
}


tunnel_info() {
  # Log URL, also make sure it appears in the container output.
  verbose "Code tunnel started at %s" "$1"
  gist_publish "$CODE_GIST_FILE" "$CODE_TIMESTAMP" <<EOF

(vs)code tunnel running, access it from your browser at the following URL:
    $1

EOF
}


# Wait for the tunnel to be started and print out its URL. All arguments are
# the ones originally given to tunnel_start, they are passed again on restarts.
tunnel_wait() {
  # _CODE_RESTART_FLAG is inherited by the when_infile subshell so tunnel_restart
  # can signal back without modifying _CODER_PIDS in the child. Only reserve a
  # unique name: the file must not exist until tunnel_restart creates it.
  _CODE_RESTART_FLAG=$(mktemp_ext restart flag)
  rm -f "$_CODE_RESTART_FLAG"
  debug "Wait for code tunnel to start..."
  while true; do
    url=$(when_infile "$_SPAWN_LOG_OFFSET" "$_SPAWN_LOG" 'E' \
            'error connecting to tunnel:' tunnel_restart \
            '(Open this link in your browser|➜\s+Open:)' - | grep -oE 'https?://.*') || true
    if [ -f "$_CODE_RESTART_FLAG" ]; then
      rm -f "$_CODE_RESTART_FLAG"
      [ "$CODE_RESTART" -lt 0 ] && break
      sleep "$CODE_RESTART"
      tunnel_start "$@"
      continue
    fi
    break
  done
  tunnel_info "$url"
}


# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="vscode tunnel starter"

# Initialize
log_init CODE

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
tunnel_wait "$@"

CODE_PID=$(spawn_latest)
trace "Code tunnel running as PID %d, waiting for it to exit.." "$CODE_PID"
spawn_wait "$CODE_PID"; # Wait for the tunnel to end.

_ret=$?
spawn_kill -t -r "cleanup"; # Kill the log relay, if any.
exit $_ret
