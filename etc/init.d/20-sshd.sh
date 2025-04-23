#!/bin/sh

# Shell sanity. Stop on errors and undefined variables.
set -eu

# Absolute location of the script where this script is located.
SSHD_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(readlink -f "$0")")")" && pwd -P )

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


# Level of verbosity, the higher the more verbose. All messages are sent to the
# file at SSHD_LOG.
: "${SSHD_VERBOSE:="${TUNNEL_VERBOSE:-"0"}"}"

# Where to send logs
: "${SSHD_LOG:="${TUNNEL_LOG:-"2"}"}"

: "${SSHD_PREFIX:="${TUNNEL_PREFIX:-"/usr/local"}"}"

: "${SSHD_USER:=""}"

: "${SSHD_SHELL:=""}"

: "${SSHD_GITHUB_USER:="${TUNNEL_GITHUB_USER:-""}"}"

: "${SSHD_PORT:="${TUNNEL_SSH:-"2222"}"}"

: "${SSHD_CONFIG_DIR:="${SSHD_PREFIX}/etc/ssh"}"

# Detach in the background
: "${SSHD_DAEMONIZE:=0}"

# Prevent detaching in the background (RESERVED for use by ourselves)
: "${_SSHD_PREVENT_DAEMONIZATION:=0}"


# shellcheck disable=SC2034 # Used from functions in common.sh
CODE_DESCR="ssh daemon startup"
while getopts "g:l:p:s:u:vh" opt; do
  case "$opt" in
    g) # GitHub user to fetch keys from
      SSHD_GITHUB_USER="$OPTARG";;
    p) # Port to listen on
      SSHD_PORT="$OPTARG";;
    l) # Where to send logs
      SSHD_LOG="$OPTARG";;
    s) # Shell to use
      SSHD_SHELL="$OPTARG";;
    u) # User to accept at ssh daemon
      SSHD_USER="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      SSHD_VERBOSE=$((SSHD_VERBOSE + 1));;
    h) # Show help
      usage 0 SSHD
      ;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done

log_init SSHD

configure_sshd() {
  as_root mkdir -p "${SSHD_CONFIG_DIR}"
  as_root chmod go-rwx "${SSHD_CONFIG_DIR}"

  as_root mkdir -p "${SSHD_PREFIX}/log"

  if [ -n "$SSHD_GITHUB_USER" ]; then
    verbose "Collecting public keys from %s" "$SSHD_GITHUB_USER"
    download "https://github.com/${SSHD_GITHUB_USER}.keys" - | as_root tee "${SSHD_CONFIG_DIR}/authorized_keys" > /dev/null
    as_root chmod go-rwx "${SSHD_CONFIG_DIR}/authorized_keys"
  fi

  verbose "Generating ssh host keys"
  as_root ssh-keygen -q -f "${SSHD_CONFIG_DIR}/ssh_host_rsa_key" -N '' -b 4096 -t rsa

  SSHD_TEMPLATE=$(mktemp)
  cat <<'EOF' > "$SSHD_TEMPLATE"
LogLevel DEBUG3
Port $PORT
HostKey $PWD/ssh_host_rsa_key
PidFile $PWD/sshd.pid

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

# Only allow those keys
AuthorizedKeysFile $PWD/authorized_keys

# Turns on sftp-server
Subsystem    sftp    /usr/lib/ssh/sftp-server

# Force the shell for the user
Match User $USER
SetEnv SHELL=$SHELL
EOF

  if [ -f "$SSHD_TEMPLATE" ]; then
    sed \
      -e "s,\$PWD,${SSHD_CONFIG_DIR},g" \
      -e "s,\$USER,${SSHD_USER},g" \
      -e "s,\$PORT,${SSHD_PORT},g" \
      -e "s,\$SHELL,${SSHD_SHELL},g" \
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
if [ -z "$SSHD_SHELL" ]; then
  SSHD_SHELL=$(getent passwd "$SSHD_USER" | cut -d: -f7)
  verbose "Using shell %s for %s in sshd" "$SSHD_SHELL" "$SSHD_USER"
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
as_root /usr/sbin/sshd -D -f "${SSHD_CONFIG_DIR}/sshd_config" -E "${SSHD_PREFIX}/log/sshd.log" &
pid_sshd=$!
verbose "sshd started with pid %s" "$pid_sshd"
