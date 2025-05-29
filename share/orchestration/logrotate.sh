#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail

# Absolute location of the script where this script is located.
LOGROTATE_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log system; do
  for d in ../../lib ../lib lib; do
    if [ -d "${LOGROTATE_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${LOGROTATE_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done

: "${XDG_STATE_HOME:="${HOME}/.local/state"}"

# All following vars have defaults here, but most will be set and inherited from
# the calling tunnel.sh script.
: "${LOGROTATE_VERBOSE:="${TUNNEL_VERBOSE:-"0"}"}"
: "${LOGROTATE_LOG:="${TUNNEL_LOG:-"2"}"}"
: "${LOGROTATE_PREFIX:="${TUNNEL_PREFIX:-"/usr/local"}"}"

# Location of the log files that will be rotated.
: "${LOGROTATE_LOGDIR:="${LOGROTATE_PREFIX}/log"}"

# Location of the logrotate status file. This is used to keep track of the last
# time the log files were rotated. It needs to be in a location that is
# accessible by the user, since logrotate is run as the user.
: "${LOGROTATE_STATUS:="${XDG_STATE_HOME}/logrotate.status"}"

# shellcheck disable=SC2034 # Used for logging/usage
CODER_DESCR="logrotate updater"
while getopts "L:s:vh-" opt; do
  case "$opt" in
    L) # Log directory
      LOGROTATE_LOGDIR="$OPTARG";;
    s) # Status file
      LOGROTATE_STATUS="$OPTARG";;
    v) # Increase verbosity, repeat to increase
      LOGROTATE_VERBOSE=$((LOGROTATE_VERBOSE + 1));;
    h) # Show help
      usage 0 LOGROTATE
      ;;
    -) # End of options, file name to follow
      break;;
    *)  # Unknown option
      usage 1
      ;;
  esac
done
shift $((OPTIND - 1))


log_init LOGROTATE

check_command logrotate || error "logrotate not found, please install it"
mkdir -p "$(dirname "$LOGROTATE_STATUS")" || error "Cannot create directory for logrotate status file %s" "$LOGROTATE_STATUS"

LWRAP="$LOGROTATE_ROOTDIR/lwrap.sh"

# Create a temporary file for the logrotate configuration, arrange to remove it
# when we are done.
config=$(mktemp -t logrotate.XXXXXX)
trap 'rm -f "$config"; trap - EXIT; exit' EXIT INT HUP TERM

# Add a header to the logrotate configuration file
cat <<'EOF' > "$config"
# Online documentation for logrotate: https://linux.die.net/man/8/logrotate

# Keep 3 weeks of logs, compress them.
rotate 3
weekly
compress

# Handle errors gracefully
missingok
notifempty

# To respect ownership and permissions, the main file will be truncated (as it
# is not written to by the root user).
copytruncate

# All our files end with .log, this will arrange for .1, .2, etc to be at a
# better location in the filenames of the rotated files.
extension .log

# Rotate the log files of the services/wrapper processes
EOF

# Find all the log files in the log directory and add them to the logrotate
# configuration file. We use a newline as the IFS separator to allow for
# spaces in the filenames.
newline=$(printf \\n)
find "$LOGROTATE_LOGDIR" -type f -name "*.log" | while IFS="$newline" read -r file; do
  if [ -f "$file" ]; then
    printf "%s {}\n" "$file" >> "$config"
  fi
done

# Now we have a configuration file, we can run logrotate on it.
"$LWRAP" logrotate -s "$LOGROTATE_STATUS" "$config"
