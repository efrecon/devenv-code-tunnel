#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
SSHD_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in common system; do
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

: "${SSHD_USER:=""}"

# GitHub user to fetch keys from
: "${SSHD_GITHUB_USER:="${TUNNEL_GITHUB_USER:-""}"}"

# Port of the SSH daemon to listen on
: "${SSHD_PORT:="${TUNNEL_SSH:-"2222"}"}"

# Type of server keys to generate. Must match -t option of ssh-keygen, e.g. dsa,
# ecdsa, ed25519, or rsa. Keys will not be re-generated if they already exist.
: "${SSHD_KEY:="ed25519"}"

# Where to store sshd data
: "${SSHD_CONFIG_DIR:="${SSHD_PREFIX}/etc/ssh"}"

# Where to store sshd logs, will be accessible by the user
: "${SSHD_LOGFILE:="${SSHD_PREFIX}/log/sshd.log"}"

# Log level to use in sshd. One of: QUIET, FATAL, ERROR, INFO, VERBOSE, DEBUG,
# DEBUG1, DEBUG2, and DEBUG3
: "${SSHD_LOGLEVEL:="INFO"}"

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


configure_sshd() {
  as_root mkdir -p "${SSHD_CONFIG_DIR}"
  SSHD_CONFIG_USER="${SSHD_CONFIG_DIR%/}/user"
  SSHD_CONFIG_SERVER="${SSHD_CONFIG_DIR%/}/server"
  make_owned_dir "$SSHD_CONFIG_USER" "$SSHD_USER"
  make_owned_dir "$SSHD_CONFIG_SERVER" "root"

  as_root mkdir -p "${SSHD_PREFIX}/log"

  if [ -n "$SSHD_GITHUB_USER" ]; then
    verbose "Collecting public keys from %s" "$SSHD_GITHUB_USER"
    download "https://github.com/${SSHD_GITHUB_USER}.keys" - > "${SSHD_CONFIG_USER}/authorized_keys"
    chmod go-rwx "${SSHD_CONFIG_USER}/authorized_keys"
  fi

  if as_root test -f "${SSHD_CONFIG_SERVER}/ssh_host_${SSHD_KEY}_key" \
      && as_root test -f "${SSHD_CONFIG_SERVER}/ssh_host_${SSHD_KEY}_key.pub"; then
    verbose "Found existing ssh host keys, skipping generation"
  else
    verbose "Generating ssh host keys"
    for f in "ssh_host_${SSHD_KEY}_key" "ssh_host_${SSHD_KEY}_key.pub"; do
      if [ -f "${SSHD_CONFIG_SERVER}/$f" ]; then
        verbose "Removing old host key %s" "${SSHD_CONFIG_SERVER}/$f"
        as_root rm -f "${SSHD_CONFIG_SERVER}/$f"
      fi
    done
    as_root ssh-keygen \
              -q \
              -C "sshd for $SSHD_USER" \
              -f "${SSHD_CONFIG_SERVER}/ssh_host_${SSHD_KEY}_key" \
              -N '' \
              -t "$SSHD_KEY"
  fi
  as_root cp -f "${SSHD_CONFIG_SERVER}/ssh_host_${SSHD_KEY}_key.pub" "${SSHD_PREFIX}/etc/ssh_host_${SSHD_KEY}_key.pub"

  verbose "Making ssh host public key at %s readable by %s" "${SSHD_PREFIX}/etc/ssh_host_${SSHD_KEY}_key.pub" "$SSHD_USER"
  as_root chown "$SSHD_USER" "${SSHD_PREFIX}/etc/ssh_host_${SSHD_KEY}_key.pub"

  SSHD_TEMPLATE=$(mktemp)
  cat <<'EOF' > "$SSHD_TEMPLATE"
LogLevel $LOGLEVEL
Port $PORT
HostKey $PWD/server/ssh_host_$KEY_key
PidFile $PWD/server/sshd.pid

# PAM is necessary for password authentication on Debian-based systems
UsePAM yes

# Allow interactive authentication (default value)
#KbdInteractiveAuthentication yes

# Same as above but for older SSH versions (default value)
#ChallengeResponseAuthentication yes

# Allow password authentication (default value)
PasswordAuthentication no

# Only allow single user
AllowUsers $USER

# Turns on sftp-server
Subsystem    sftp    /usr/lib/ssh/sftp-server

# Force the shell for the user
Match User $USER
  # Only allow those keys
  AuthorizedKeysFile $PWD/user/authorized_keys
EOF

  if [ -f "$SSHD_TEMPLATE" ]; then
    sed \
      -e "s,\$LOGLEVEL,${SSHD_LOGLEVEL},g" \
      -e "s,\$PWD,${SSHD_CONFIG_DIR},g" \
      -e "s,\$USER,${SSHD_USER},g" \
      -e "s,\$PORT,${SSHD_PORT},g" \
      -e "s,\$KEY,${SSHD_KEY},g" \
      "$SSHD_TEMPLATE" | as_root tee "${SSHD_CONFIG_DIR}/sshd_config" > /dev/null
    as_root chmod go-rwx "${SSHD_CONFIG_DIR}/sshd_config"
    rm -f "$SSHD_TEMPLATE"
  fi
}


if ! check_command "sshd"; then
  exit 0
fi

if [ -z "$SSHD_USER" ]; then
  SSHD_USER=$(id -un)
  verbose "Restricting sshd to user %s" "$SSHD_USER"
fi

# If we are to daemonize, do it now and exit. Export all our variables to the
# daemon so it starts the same way this script was started.
if ! is_true "$_SSHD_PREVENT_DAEMONIZATION" && is_true "$SSHD_DAEMONIZE"; then
  # Do not daemonize the daemon!
  _SSHD_PREVENT_DAEMONIZATION=1
  SSHD_DAEMONIZE=0
  daemonize SSHD "$@"
fi

configure_sshd
touch "$SSHD_LOGFILE"
as_root /usr/sbin/sshd -D -f "${SSHD_CONFIG_DIR}/sshd_config" -E "$SSHD_LOGFILE" "$@" &
pid_sshd=$!
verbose "sshd started with pid %s. Logs at %s" "$pid_sshd" "$SSHD_LOGFILE"
