#!/bin/sh

# Restart the script in the background, with the same arguments. You may pass a
# leading prefix of (local) variables to export to the process (defaults to the
# cleanname of this script, in uppercase). All other arguments MUST be the ones
# that were passed to the script.
daemonize() {
  bin_name
  _namespace=${1:-$(to_upper "$CODER_BIN")}
  [ "$#" -gt 0 ] && shift

  export_varset "$_namespace"
  export_varset "_$_namespace"

  # Restart ourselves in the background, with same arguments.
  (
    nohup "$0" "$@" </dev/null >/dev/null 2>&1 &
  )

  exit 0
}

init_list() {
  [ -z "$1" ] && error "init_list: No directory given"

  find "$1" -maxdepth 1 -type f -executable -name "${2:-"*.sh"}" |
    sed -E -e 's|^.*/(.*\.sh)|\1|g' |
    sort |
    sed -E -e 's|^[0-9]+-||g' -e 's|\.sh$||g' |
    tr '\n' ' '
}


init_get() {
  [ -z "$1" ] && error "init_get: No directory given"
  [ -z "$2" ] && error "init_get: No init script given"

  find "$1" -maxdepth 1 -type f -executable -name "*${2}.sh"
}


# Supervise a script, restarting it when it exits with a non-zero status.
# $1 is the human-readable name of the script
# $2 is the path to the script
# Remaining arguments are passed to the script, as is.
_supervise() {
  _sup_name=$1
  _sup_script=$2
  shift 2
  _delay=0
  while true; do
    ${INSTALL_OPTIMIZE:-} "$_sup_script" "$@"
    _rc=$?
    [ "$_rc" -eq 0 ] && break
    debug "%s exited with %d, restarting in %d seconds" "$_sup_name" "$_rc" "$_delay"
    [ "$_delay" -gt 0 ] && sleep "$_delay"
    if [ "$_delay" -eq 0 ]; then
      _delay=1
    elif [ "$((_delay * 2))" -gt 60 ]; then
      _delay=60
    else
      _delay=$((_delay * 2))
    fi
  done
}


# Start dependency scripts
# $1 is the type of script, used in messages and for background/foreground
# $2 is the directory to look for scripts
# $3 is the list of scripts to start, when empty all scripts matching $4 will be started
# $4 is the pattern to match scripts against, default is *.sh
# $5 is a boolean wether to start the script in the background or not.
# Remaining arguments are passed to the scripts, as is.
delegate() {
  [ -z "${1:-}" ] && error "delegate: No type given"
  [ -z "${2:-}" ] && error "delegate: No directory given"

  _human_t=$1
  _scripts_d=$2
  [ -z "${3:-}" ] && _deps="$(init_list "$_scripts_d" "${4:-"*.sh"}")" || _deps="$3"
  _bg_run=${5:-"0"}

  # Jump to arguments to be passed to the scripts.
  if [ "$#" -gt 5 ]; then
    shift 5
  else
    shift "$#"
  fi
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
          debug "Spawning %s using %s" "$_s" "$_script"
          _supervise "$_s" "$_script" "$@" &
          info "Supervising %s %s with PID $!" "$_human_t" "$_s"
          printf %s\\t%d\\n "$_s" "$!"
        else
          debug "Running %s using %s" "$_s" "$_script"
          if ! ${INSTALL_OPTIMIZE:-} "$_script" "$@"; then
            error "%s %s failed" "$_human_t" "$_script"
          fi
          printf %s\\n "$_s"
        fi
      else
        warn "%s %s is not executable" "$_human_t" "$_script"
      fi
    done
  fi
}
