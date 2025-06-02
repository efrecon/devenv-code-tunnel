#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
SSHD_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common delegate system; do
  for d in ../../lib ../lib lib; do
    if [ -d "${SSHD_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${SSHD_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

# Arrange to set the CODER_BIN variable to the name of the script
bin_name


# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at SSHD_LOG.
: "${SSHD_VERBOSE:="${TUNNEL_VERBOSE:-"0"}"}"

# Where to send logs
: "${SSHD_LOG:="${TUNNEL_LOG:-"2"}"}"

: "${SSHD_PREFIX:="${TUNNEL_PREFIX:-"/usr/local"}"}"
: "${SSHD_USER_PREFIX:="${TUNNEL_USER_PREFIX:-"${HOME}/.local"}"}"

: "${SSHD_REEXPOSE:="${TUNNEL_REEXPOSE:-"sshd"}"}"

: "${SSHD_USER:=""}"

# GitHub user to fetch keys from
: "${SSHD_GITHUB_USER:="${TUNNEL_GITHUB_USER:-""}"}"

# Port of the SSH daemon to listen on
: "${SSHD_PORT:="${TUNNEL_SSH:-"2222"}"}"

# Type of server keys to generate. Must match -t option of ssh-keygen, e.g. dsa,
# ecdsa, ed25519, or rsa. Keys will not be re-generated if they already exist.
: "${SSHD_KEY:="ed25519"}"

# Where to store sshd logs, will be accessible by the user
: "${SSHD_LOGFILE:="${SSHD_PREFIX}/log/sshd.log"}"

# Log level to use in sshd. One of: QUIET, FATAL, ERROR, INFO, VERBOSE, DEBUG,
# DEBUG1, DEBUG2, and DEBUG3
: "${SSHD_LOGLEVEL:="DEBUG3"}"

# Environment file to load for reading defaults from.
: "${SSHD_DEFAULTS:="${SSHD_ROOTDIR}/../${CODER_BIN}.env"}"

# Detach in the background
: "${SSHD_DAEMONIZE:=0}"

# Prevent detaching in the background (RESERVED for use by ourselves)
: "${_SSHD_PREVENT_DAEMONIZATION:=0}"


# shellcheck disable=SC2034 # Used from functions in common.sh
CODE_DESCR="ssh daemon startup"
while getopts "g:k:l:p:u:vh-" opt; do
  case "$opt" in
    g) # GitHub user to fetch keys from
      SSHD_GITHUB_USER="$OPTARG";;
    k) # Type of key to use, must match -t option of ssh-keygen!
      SSHD_KEY="$OPTARG";;
    p) # Port to listen on
      SSHD_PORT="$OPTARG";;
    l) # Where to send logs
      SSHD_LOG="$OPTARG";;
    u) # User to accept at ssh daemon
      SSHD_USER="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      SSHD_VERBOSE=$((SSHD_VERBOSE + 1));;
    h) # Show help
      usage 0 SSHD;;
    -) # End of options, everything else passed to sshd blindly
      break;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done
shift $((OPTIND - 1))

log_init SSHD

# Load defaults
[ -n "$SSHD_DEFAULTS" ] && read_envfile "$SSHD_DEFAULTS" SSHD

make_owned_dir() {
  as_root mkdir -p "$1"
  as_root chown "$2" "$1"
  as_root chmod go-rwx "$1"
}

collect_github_keys() {
  if [ -n "$SSHD_GITHUB_USER" ]; then
    debug "Collecting public keys from %s" "$SSHD_GITHUB_USER"
    ls -la "$HOME"
    mkdir -p "$(dirname "$1")"
    download "https://github.com/${SSHD_GITHUB_USER}.keys" - >> "$1"
    chmod go-rwx "$1"
    verbose "Collected public keys from '%s' to: %s" "$SSHD_GITHUB_USER" "$1"
  fi
}

generate_dropbear_keys() {
  if [ -f "$2" ] && [ -f "${2}.pub" ]; then
    verbose "Found existing pair of keys at '%s', skipping generation" "$2"
  else
    verbose "Generating dropbear host keys in %s" "${SSHD_CONFIG_SERVER}"
    for f in "$2" "${2}.pub"; do
      if [ -f "$f" ]; then
        verbose "Removing old host key %s" "$f"
        as_user "$1" rm -f "$f"
      fi
    done
    as_user "$1" dropbearkey \
                    -t "$SSHD_KEY" \
                    -f "$2" \
                    -C "sshd for $SSHD_USER"
  fi
}

generate_server_keys() {
  verbose "Generating ssh host keys in %s" "${SSHD_CONFIG_SERVER}"
  for f in "ssh_host_${SSHD_KEY}_key" "ssh_host_${SSHD_KEY}_key.pub"; do
    if [ -f "${SSHD_CONFIG_SERVER}/$f" ]; then
      verbose "Removing old host key %s" "${SSHD_CONFIG_SERVER}/$f"
      as_user "$1" rm -f "${SSHD_CONFIG_SERVER}/$f"
    fi
  done
  as_user "$1" ssh-keygen \
                  -q \
                  -C "sshd for $SSHD_USER" \
                  -f "${SSHD_CONFIG_SERVER}/ssh_host_${SSHD_KEY}_key" \
                  -N '' \
                  -t "$SSHD_KEY"
}

# TODO: Keep dropbear, get rid of sshd. Run it as root for ports under 1024. Perhaps pass the user to this function?
configure_dropbear() {
  # Create the directories with proper permissions
  mkdir -p "$SSHD_CONFIG_USER" "$SSHD_CONFIG_SERVER"
  chmod go-rwx "$SSHD_CONFIG_USER" "$SSHD_CONFIG_SERVER"

  # Ensure we will be able to log
  mkdir -p "$(dirname "$SSHD_LOGFILE")"

  # Allow the user to login, pick keys from GitHub if given
  for _crypto in rsa ecdsa ed25519; do
    if [ -f "$HOME/.ssh/id_${_crypto}.pub" ]; then
      cat "$HOME/.ssh/id_${_crypto}.pub" >> "${SSHD_CONFIG_USER}/authorized_keys"
      verbose "Authorized existing %s to login" "$HOME/.ssh/id_${_crypto}.pub"
    fi
  done
  collect_github_keys "${SSHD_CONFIG_USER}/authorized_keys"
  sort -u -o "${SSHD_CONFIG_USER}/authorized_keys" "${SSHD_CONFIG_USER}/authorized_keys"
  chmod go-rwx "${SSHD_CONFIG_USER}/authorized_keys"

  # Generate the host keys if they do not exist, copy server public key to known
  # location.
  generate_dropbear_keys "$SSHD_USER" "${SSHD_CONFIG_SERVER}/ssh_host_${SSHD_KEY}_key"
  # TODO: remove this, change in dependencies?
  cp -f "${SSHD_CONFIG_SERVER}/ssh_host_${SSHD_KEY}_key.pub" "${SSHD_USER_PREFIX}/etc/ssh_host_${SSHD_KEY}_key.pub"
}

if ! check_command "dropbear"; then
  exit 0
fi


# TODO: Once done, merge this branch into the feature/use-krun branch.

if [ -z "$SSHD_USER" ]; then
  SSHD_USER=$(id -un)
  verbose "Restricting sshd to user %s" "$SSHD_USER"
fi

SSHD_ORCHESTRATION_DIR=${SSHD_ROOTDIR}/../../share/orchestration
SSHD_LOGGER=${SSHD_ORCHESTRATION_DIR}/logger.sh
[ -x "$SSHD_LOGGER" ] || error "Cannot find logger.sh"

# If we are to daemonize, do it now and exit. Export all our variables to the
# daemon so it starts the same way this script was started.
if ! is_true "$_SSHD_PREVENT_DAEMONIZATION" && is_true "$SSHD_DAEMONIZE"; then
  # Do not daemonize the daemon!
  _SSHD_PREVENT_DAEMONIZATION=1
  SSHD_DAEMONIZE=0
  daemonize SSHD "$@"
fi

# TODO: "Killer" command for krun is: podman container run -it --rm --runtime=krun --userns=keep-id:uid=1000,gid=1000 --name devenv --hostname blue-devenv -v /home/emmanuel/.ssh/id_ed25519:/home/coder/.ssh/id_ed25519:Z,ro -v /home/emmanuel/.ssh/id_ed25519.pub:/home/coder/.ssh/id_ed25519.pub:Z,ro -v devenv:/home/coder:Z  -e TUNNEL_CLOUDFLARE_PROTOCOL=http2 -p 2222:2222 localhost/code_tunnel_minimal:latest -S 'system dockerd sshd cron' -vv -L sshd -g efrecon

if [ "$SSHD_PORT" -gt 1024 ]; then
  SSHD_CONFIG_DIR=${SSHD_USER_PREFIX}/etc/ssh
  SSHD_CONFIG_USER="${SSHD_CONFIG_DIR%/}/user"
  SSHD_CONFIG_SERVER="${SSHD_CONFIG_DIR%/}/server"
  SSHD_LOGFILE=${SSHD_PREFIX}/log/sshd.log
  configure_dropbear
  touch "$SSHD_LOGFILE"
  verbose "Starting dropbear sshd for user %s on port %s" "$SSHD_USER" "$SSHD_PORT"
  # TODO: Restrict to same group as the one of the user?
  dropbear \
    -r "${SSHD_CONFIG_SERVER}/ssh_host_${SSHD_KEY}_key" \
    -D "${SSHD_CONFIG_USER}" \
    -p "$SSHD_PORT" \
    -G "$(id -gn)" \
    -s \
    -g \
    -P "${SSHD_CONFIG_SERVER}/sshd.pid" \
    -E \
    "$@" 2>>"$SSHD_LOGFILE"
  pid_sshd=$(cat "${SSHD_CONFIG_SERVER}/sshd.pid")
else
  # TODO: Rewrite with dropbear
  SSHD_CONFIG_DIR=${SSHD_PREFIX}/etc/ssh
  SSHD_LOGFILE=${SSHD_PREFIX}/log/sshd.log
  configure_sshd_root
  touch "$SSHD_LOGFILE"
  as_root /usr/sbin/sshd -D -f "${SSHD_CONFIG_DIR}/sshd_config" -E "$SSHD_LOGFILE" "$@" &
  pid_sshd=$!
fi
if [ -z "$SSHD_REEXPOSE" ] || printf %s\\n "$SSHD_REEXPOSE" | grep -qF 'sshd'; then
  verbose "sshd started with pid %s, forwarding logs from %s" "$pid_sshd" "$SSHD_LOGFILE"
  "$SSHD_LOGGER" -s "sshd" -- "$SSHD_LOGFILE" &
else
  verbose "sshd started with pid %s. Logs at %s" "$pid_sshd" "$SSHD_LOGFILE"
fi
