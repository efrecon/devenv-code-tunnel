#!/bin/sh

# Note: This is a library, not a standalone script. It is meant to be sourced
# from other scripts.

# The behavior of the functions in this library can be controlled by the
# following environment variables:
# CODER_BIN: The name of the script, used for logging here.
# CODER_VERBOSE: The verbosity level, the higher the more verbose.
# CODER_LOG: Where to send logs. 0: none, 1: stdout, 2: stderr, <file>

# Given a path, return it's clean base name, i.e. no extension, and no leading
# ordering numbers, i.e. 01-xxxx.sh -> xxxx
cleanname() {
  _clean_name=$(basename "$1")
  _clean_name=${_clean_name%%.*}
  _clean_name=${_clean_name#*-}
  printf %s\\n "$_clean_name"
}

# Arrange to set the CODER_BIN variable to the cleanname of the script. This
# is used both for logging in this library, but also for following the
# conventions between the name of the scripts and env. variables that they
# recognise elsewhere in the project.
# shellcheck disable=SC2120 # Take none or one argument
bin_name() {
  if [ -z "${CODER_BIN:-}" ]; then
    CODER_BIN=$(cleanname "${1:-"$0"}")
  fi
}

# Print usage information and exit. Uses the comments in the script to show the
# options.
usage() {
  # This uses the comments behind the options to show the help. Not extremly
  # correct, but effective and simple.
  echo "$(basename "$0") -- ${CODER_DESCR:-"Part of the code tunnelled project"}" && \
    grep "[[:space:]].) #" "$0" |
    sed 's/#//' |
    sed -r 's/([a-zA-Z-])\)/-\1/'
  if [ -n "${2:-}" ]; then
    printf '\nCurrent state:\n'
    set | grep -E "^${2}_" | sed -E 's/^([A-Z])/  \1/g'
  fi
  exit "${1:-0}"
}

# PML: Poor Man's Logging...

# Print a log line. The first argument is a (preferred) 3 letters human-readable
# log-level. All other arguments are passed blindly to printf, a builtin
# function.
_logline() {
  # Capture level and shift it away, rest will be passed blindly to printf
  _lvl=${1:-LOG}; shift
  bin_name
  # shellcheck disable=SC2059 # We want to expand the format string
  printf '>>>>>%s<<<<< [%s] [%s] %s\n' \
    "$CODER_BIN" \
    "$_lvl" \
    "$(date +'%Y%m%d-%H%M%S')" \
    "$(printf "$@")"
}

# Log a line to either stdout, stderr or a file. All arguments are blindly
# passed to _logline.
_log() {
  case "$CODER_LOG" in
    0) return 0;;
    1) _logline "$@" >&1;;
    2) _logline "$@" >&2;;
    "") _logline "$@";;
    *) _logline "$@" >> "$CODER_LOG";;
  esac
}
# log level functions, pass further to _log
trace() { if [ "${CODER_VERBOSE:-0}" -ge "3" ]; then _log TRC "$@"; fi; }
debug() { if [ "${CODER_VERBOSE:-0}" -ge "2" ]; then _log DBG "$@"; fi; }
verbose() { if [ "${CODER_VERBOSE:-0}" -ge "1" ]; then _log NFO "$@"; fi; }
info() { if [ "${CODER_VERBOSE:-0}" -ge "1" ]; then _log NFO "$@"; fi; }
warn() { _log WRN "$@"; }
error() { _log ERR "$@" && exit 1; }

# Get the content of the variable which name is passed as an argument.
get_var() { eval printf "%s\\\n" "\$${1:-}" || true; }

# Initialize the logging system. When an argument is passed, it is used to find
# the variables that contain verbosity and logging output information. When none
# given, will default to the main script name in uppercase.
log_init() {
  bin_name
  CODER_VERBOSE=$(get_var "${1:-"$(to_upper "$CODER_BIN")"}_VERBOSE")
  CODER_LOG=$(get_var "${1:-"$(to_upper "$CODER_BIN")"}_LOG")
}

# Source an environment file. Re-initialise the logging system in case the
# variables controlling logging (level and output) would have been changed.
read_envfile() {
  if [ -f "$1" ]; then
    verbose "Reading environment file: %s" "$1"
    # shellcheck source=/dev/null
    . "$1"
    log_init "${2:-}"
  fi
}

# Check if a command is available. If not, print a warning and return 1.
check_command() {
  trace "Checking $1 is an accessible command"
  if ! command -v "$1" >/dev/null 2>&1; then
    warn "Command not found: %s" "$1"
    return 1
  fi
}

# Run the command passed as arguments as root, i.e. with sudo if
# available/necessary. Generate an error if not possible.
as_root() {
  if [ "$(id -u)" = 0 ]; then
    "$@"
  elif check_command sudo; then
    verbose "Running elevated command: %s" "$*"
    sudo "$@"
  else
    error "This script requires root privileges"
  fi
}


# shellcheck disable=SC2120 # Take none or one argument
to_lower() {
  if [ -z "${1:-}" ]; then
    tr '[:upper:]' '[:lower:]'
  else
    printf %s\\n "$1" | to_lower
  fi
}

# shellcheck disable=SC2120 # Take none or one argument
to_upper() {
  if [ -z "${1:-}" ]; then
    tr '[:lower:]' '[:upper:]'
  else
    printf %s\\n "$1" | to_upper
  fi
}

# Check if the argument is a true value. The following are considered true: 1,
# true, yes, y, on, t (case insensitive).
is_true() {
  case "$(to_lower "${1:-}")" in
    1 | true | yes | y | on | t) return 0;;
    *) return 1;;
  esac
}

# Restart the script in the background, with the same arguments. You may pass a
# leading prefix of (local) variables to export to the process (defaults to the
# cleanname of this script, in uppercase). All other arguments MUST be the ones
# that were passed to the script.
daemonize() {
  bin_name
  _namespace=${1:-$(to_upper "$CODER_BIN")}
  shift

  while IFS= read -r varname; do
    debug "Exporting $varname to prepare for daemonization"
    # shellcheck disable=SC2163 # We want to export the name of the variable
    export "$varname"
  done <<EOF
$(set | grep -E "^(${_namespace}_)" | sed -E 's/^([A-Z_]+)=.*/\1/g')
EOF

  # Restart ourselves in the background, with same arguments.
  (
    set -m
    nohup "$0" -- "$@" </dev/null >/dev/null 2>&1 &
  )

  exit 0
}

# Find the executable passed as an argument in the PATH variable and print it if
# it is not the second argument, typically $0. This will not work if there is a
# directory containing a line break in the PATH (but... why?!)
find_exec() {
  while IFS= read -r dir; do
    if [ -n "${dir}" ] && [ -d "${dir}" ] && [ -x "${dir%/}/$1" ]; then
      if [ -z "${2:-}" ]; then
        printf %s\\n "${dir%/}/$1"
        break
      elif [ "${dir%/}/$1" != "$2" ]; then
        printf %s\\n "${dir%/}/$1"
        break
      fi
    fi
  done <<EOF
$(printf %s\\n "$PATH"|tr ':' '\n')
EOF
}

# Verify that file at $1 has sha512 checksum $2. When $3 is present, it is used
# to provide a description of the file. When $4 is present, it is the mode to
# use for the file (otherwise text mode is used, which should work in most
# cases). When no checksum is provided, a warning is issued.
checksum() {
  if [ -n "${2:-}" ]; then
    if ! printf "%s %s%s\n" "$2" "${4:-" "}" "$1" | sha512sum -c - >/dev/null; then
      rm -f "$1"
      error "Checksum mismatch for ${3:-$1}"
    else
      debug "Checksum verified for ${3:-$1}"
    fi
  else
    warn "No checksum provided for ${3:-$1}. Skipping verification."
  fi
}

# Download the URL passed as first argument to the file passed as second.
# Defaults to stdout if no file.
download() {
  debug "Downloading $1"
  $INSTALL_OPTIMIZE curl -sSL "$1" --output "${2:-"-"}"
}


# Install a script from the internet. This is a convenience function that
# generates a log line to make this more appearent.
internet_install() {
  _tmp=$(mktemp -t "${2:-"$(basename "$1")"}".XXXXXX)
  download "$1" "$_tmp"
  if [ -n "${3:-}" ]; then
    checksum "$_tmp" "$3" "$2"
  fi
  verbose "Running downloaded script $_tmp"
  $INSTALL_OPTIMIZE bash -- "$_tmp"
  rm -f "$_tmp"
}


install_packages() {
  verbose "Installing packages: $*"
  $INSTALL_OPTIMIZE apk add --no-cache "$@"
}
