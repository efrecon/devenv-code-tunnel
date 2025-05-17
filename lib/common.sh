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
  _clean_name=${_clean_name##*-}
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
# shellcheck disable=SC2120 # We just want to use the default value...
_logtag() {
  _CODER_BINTAG=$CODER_BIN
  while [ "$(printf %s "$_CODER_BINTAG" | wc -c)" -lt "${1:-14}" ]; do
    _CODER_BINTAG=">${_CODER_BINTAG}<"
  done
  _CODER_BINTAG=$(printf %s "$_CODER_BINTAG" | cut -c "1-${1:-14}")
}

# Print a log line. The first argument is a (preferred) 3 letters human-readable
# log-level. All other arguments are passed blindly to printf, a builtin
# function.
_logline() {
  # Capture level and shift it away, rest will be passed blindly to printf
  _lvl=${1:-LOG}; shift
  bin_name
  [ -z "${_CODER_BINTAG:-}" ] && _logtag
  # shellcheck disable=SC2059 # We want to expand the format string
  printf '%s [%s] [%s] %s\n' \
    "$_CODER_BINTAG" \
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

reprint() {
  while IFS= read -r line; do
    _log "" "$line"
    if [ -n "${1:-}" ]; then
      printf %s\\n "$line" >>"$1"
    fi
  done
}

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

  export_varset "$_namespace"

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
  [ -z "$1" ] && error "find_exec: no command given"
  if command -v "$1" >/dev/null; then
    if [ -z "${2:-}" ]; then
      # shellcheck disable=SC2046 # We want to expand the command
      command -v "$1"
    elif [ "$(command -v "$1")" != "$2" ]; then
      command -v "$1"
    fi
  fi
}


# Download the URL passed as first argument to the file passed as second.
# Defaults to stdout if no file.
download() {
  [ -z "$1" ] && error "download: no url given"
  debug "Downloading $1"
  ${INSTALL_OPTIMIZE:-} curl -sSL "$1" --output "${2:-"-"}"
}


assert_version() {
  if printf %s\\n "${1:-}" | grep -qE '^[0-9]+(\.[0-9]+){0,}$'; then
    return 0
  else
    error "Version ${1:-} is not a valid version number"
  fi
}


generate_random() {
  LC_ALL=C tr -dc "${2:-"a-zA-Z0-9"}" < /dev/urandom | head -c "${1:-16}"
}


find_inpath() {
  [ -z "$1" ] && error "find_inpath: no bin given"
  _prg=$1; shift
  if command -v "$_prg" >/dev/null; then
    command -v "$_prg"
    return 0
  else
    while [ "$#" != 0 ]; do
      trace "Checking ${1%/}/bin/${_prg}"
      if [ -x "${1%/}/bin/${_prg}" ]; then
        printf "%s\n" "${1%/}/bin/${_prg}"
        return 0
      fi
      shift
    done
  fi
  warn "Cannot find %s in PATH: %s or standard locations" "$_prg" "$PATH"
}


# Export all variables that start with a prefix so that they are available
# to subprocesses
export_varset() {
  [ -z "$1" ] && error "export_varset: no var prefix given"
  while IFS= read -r varname; do
    # shellcheck disable=SC2163 # We want to export the name of the variable
    export "$varname"
  done <<EOF
$(set | grep "^${1}_" | sed -E 's/^([A-Z_]+)=.*/\1/g')
EOF
}

unset_varset() {
  [ -z "$1" ] && error "export_varset: no var prefix given"
  while IFS= read -r varname; do
    # shellcheck disable=SC2163 # We want to unset the name of the variable
    unset "$varname"
  done <<EOF
$(set | grep "^${1}_" | sed -E 's/^([A-Z_]+)=.*/\1/g')
EOF
}


init_list() {
  [ -z "$1" ] && error "init_list: No directory given"

  find "$1" -type f -executable -maxdepth 1 -name "${2:-"*.sh"}" |
    sed -E -e 's|^.*/(.*\.sh)|\1|g' |
    sort |
    sed -E -e 's|^[0-9]+-||g' -e 's|\.sh$||g' |
    tr '\n' ' '
}


init_get() {
  [ -z "$1" ] && error "init_get: No directory given"
  [ -z "$1" ] && error "init_get: No init script given"

  find "$1" -type f -executable -maxdepth 1 -name "*${2}.sh"
}


# Start dependency scripts
# $1 is the type of script, used in messages and for background/foreground
# $2 is the directory to look for scripts
# $3 is the list of scripts to start, when empty all scripts matching $4 will be started
# $4 is the pattern to match scripts against, default is *.sh
# $5 is a boolean wether to start the script in the background or not.
# Remaining arguments are passed to the scripts, as is.
start_deps() {
  [ -z "${1:-}" ] && error "start_deps: No type given"
  [ -z "${2:-}" ] && error "start_deps: No directory given"

  _human_t=$1
  _scripts_d=$2
  [ -z "${3:-}" ] && _deps="$(init_list "$_scripts_d" "${4:-"*.sh"}")" || _deps="$3"
  _bg_run=${5:-"0"}

  shift 5 || shift "$#"
  if [ "$_deps" = "-" ]; then
    verbose "Starting of %s scripts disabled" "$_human_t"
  else
    verbose "Starting %s scripts in %s: %s" "$_human_t" "$_scripts_d" "$_deps"

    for _s in $_deps; do
      _script=$(init_get "$_scripts_d" "$_s")
      if [ -z "$_script" ]; then
        warn "%s %s not found in %s" "$_human_t" "$_s" "$_scripts_d"
        continue
      fi
      if [ -x "$_script" ]; then
        # TODO: Log the output to files?
        if is_true "$_bg_run"; then
          verbose "Spawning %s using %s" "$_s" "$_script"
          ${INSTALL_OPTIMIZE:-} "$_script" "$@" &
        else
          verbose "Running %s using %s" "$_s" "$_script"
          ${INSTALL_OPTIMIZE:-} "$_script" "$@"
        fi
        printf %s\\n "$_s"
      else
        warn "%s %s is not executable" "$_human_t" "$_script"
      fi
    done
  fi
}

wait_file() {
  [ -z "${1:-}" ] && error "wait_file: No file path given"
  while ! test -"${2:-f}" "$1"; do
    sleep 1
  done
  trace "Path at %s tested positive for -%s" "$1" "${2:-f}"
}

wait_infile() {
  [ -z "${1:-}" ] && error "wait_infile: No file path given"
  [ -z "${2:-}" ] && error "wait_infile: No expression provided"
  wait_file "$1"
  while ! grep -"${3:-E}" "$2" "$1"; do
    sleep 1
  done | head -n 1
}

wait_process_end() {
  [ -z "${1:-}" ] && error "wait_process_end: No PID given"
  while kill -0 "$1"; do
    sleep 1
  done
}

check_int() {
  [ -z "${1:-}" ] && error "check_int: No integer argument given"
  while [ "$#" -gt 0 ]; do
    if ! printf %s\\n "$1" | grep -qE '^-?[0-9]+$'; then
      error "check_int: %s is not a valid integer" "$1"
    fi
    shift
  done
}
