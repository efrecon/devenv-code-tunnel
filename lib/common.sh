#!/bin/sh

# Note: This is a library, not a standalone script. It is meant to be sourced
# from other scripts.


# Source an environment file. Re-initialise the logging system in case the
# variables controlling logging (level and output) would have been changed.
read_envfile() {
  if [ -f "$1" ]; then
    debug "Reading environment file: %s" "$1"
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
  ${INSTALL_OPTIMIZE:-} curl -fsSL "$1" --output "${2:-"-"}"
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


check_int() {
  [ -z "${1:-}" ] && error "check_int: No integer argument given"
  while [ "$#" -gt 0 ]; do
    if ! printf %s\\n "$1" | grep -qE '^-?[0-9]+$'; then
      error "check_int: %s is not a valid integer" "$1"
    fi
    shift
  done
}
