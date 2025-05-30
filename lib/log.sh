#!/bin/sh

# Note: This is a library, not a standalone script. It is meant to be sourced
# from other scripts.

# The behavior of the functions in this library can be controlled by the
# following environment variables:
# CODER_BIN: The name of the script, used for logging here.
# CODER_VERBOSE: The verbosity level, the higher the more verbose.
# CODER_LOG: Where to send logs. 0: none, 1: stdout, 2: stderr, <file>
# CODER_INTERACTIVE: Whether to use colours in the output. 0: no, 1: yes.

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

# Colourisation support for logging and output.
_colour() {
  if [ "${CODER_INTERACTIVE:-0}" = "1" ]; then
    printf '\033[1;%sm%b\033[0m' "$1" "$2"
  else
    printf -- "%b" "$2"
  fi
}
green() { _colour "32" "$1"; }
red() { _colour "31" "$1"; }
yellow() { _colour "33" "$1"; }
blue() { _colour "34" "$1"; }
magenta() { _colour "35" "$1"; }
cyan() { _colour "36" "$1"; }
dark_gray() { _colour "90" "$1"; }
light_gray() { _colour "37" "$1"; }


# Print usage information and exit. Uses the comments in the script to show the
# options.
usage() {
  # This uses the comments behind the options to show the help. Not extremly
  # correct, but effective and simple.
  echo "$(basename "$0") -- ${CODER_DESCR:-"Part of the code tunnelled project"}" && \
    grep "[[:space:]].) #" "$0" |
    sed 's/#//' |
    sed -E 's/([a-zA-Z-])\)/-\1/'
  if [ -n "${2:-}" ]; then
    printf '\nCurrent state:\n'
    set | grep -E "^${2}_" | sed -E 's/^([A-Z])/  \1/g'
  fi
  exit "${1:-0}"
}

# shellcheck disable=SC2120 # We just want to use the default value...
_logtag() {
  _CODER_BINTAG=$CODER_BIN
  while [ "${#_CODER_BINTAG}" -lt "${1:-14}" ]; do
    _CODER_BINTAG=">${_CODER_BINTAG}<"
  done
  _CODER_BINTAG=$(printf %s "$_CODER_BINTAG" | cut -c "1-${1:-14}")
  _CODER_BINTAG=$(printf %s "$_CODER_BINTAG" | sed -E "s/>/$(dark_gray ">")/g")
  _CODER_BINTAG=$(printf %s "$_CODER_BINTAG" | sed -E "s/</$(dark_gray "<")/g")
}

# Print a log line. The first argument is a (preferred) 3 letters human-readable
# log-level. All other arguments are passed blindly to printf, a builtin
# function.
_logline() {
  # Capture level, colorize it and shift it away, rest will be passed blindly to
  # printf
  case "${1:-}" in
    TRC) _lvl=$(dark_gray "TRC") ;;
    DBG) _lvl=$(light_gray "DBG") ;;
    NFO) _lvl=$(blue "NFO") ;;
    WRN) _lvl=$(red "WRN") ;;
    ERR) _lvl=$(magenta "ERR") ;;
    *) _lvl=$(light_gray "${1:-LOG}") ;;
  esac
  shift

  bin_name
  [ -z "${_CODER_BINTAG:-}" ] && _logtag

  # shellcheck disable=SC2059 # We want to expand the format string
  printf '%s [%s] [%s] %s\n' \
    "$_CODER_BINTAG" \
    "$_lvl" \
    "$(dark_gray "$(date +'%Y%m%d-%H%M%S')")" \
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
    *) CODER_INTERACTIVE=0 _logline "$@" >> "$CODER_LOG";;
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

  # When run at the terminal, the default is to set CODER_INTERACTIVE to be 1,
  # turning on colouring for all calls to the colouring functions contained here.
  if [ -z "${CODER_INTERACTIVE:-}" ]; then
    if [ -t "$CODER_LOG" ]; then
        CODER_INTERACTIVE=1
    else
        CODER_INTERACTIVE=0
    fi
  fi
}

