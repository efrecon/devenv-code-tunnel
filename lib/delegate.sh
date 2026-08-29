#!/bin/sh

: "${_CODER_PIDS:=}"
: "${_CODER_TRAPPED:=0}"

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

_spawn_signal() {
  for _pid in $_CODER_PIDS; do
    debug "Forwarding signal %s to PID %d" "$1" "$_pid"
    kill "-$1" "$_pid" 2>/dev/null || true
  done
}

# Only called for TERM/EXIT, not INT: terminal already delivered INT to the group
spawn_wait() {
  _ret=0
  for _pid in $_CODER_PIDS; do
    # Re-enter wait if interrupted by a signal before the process actually exits
    while kill -0 "$_pid" 2>/dev/null; do
      wait "$_pid" 2>/dev/null
      _wrc=$?
      if [ "$_wrc" -le 127 ]; then
        _ret=$_wrc
        break
      fi
    done
  done
  _CODER_PIDS=; # Clear the list of PIDs, so we don't try to wait for them again
  unset _pid || true
  debug "All spawned processes exited, returning %d" "$_ret"
  return "$_ret"
}

spawn() {
  [ -z "${1:-}" ] && error "spawn: No executable given"
  [ -x "$1" ] || error "spawn: $1 is not executable"

  _bin=$1
  shift
  trace "Spawning %s with arguments: %s" "$_bin" "$*"
  "$_bin" "$@" &
  _spawned=$!
  # Prune dead PIDs before appending, so the list only holds live processes
  _alive_pids=
  for _pid in $_CODER_PIDS; do
    kill -0 "$_pid" 2>/dev/null && _alive_pids="$_alive_pids $_pid" || true
  done
  _CODER_PIDS="$_alive_pids $_spawned"
  debug "Spawned %s with PID %d" "$_bin" "$_spawned"

  if [ "$_CODER_TRAPPED" = "0" ]; then
    trap '_spawn_signal HUP;  trap - HUP;  kill -HUP  $$' HUP
    trap '_spawn_signal INT;  trap - INT;  kill -INT  $$' INT
    trap '_spawn_signal TERM; spawn_wait || true; trap - TERM; kill -TERM $$' TERM
    trap '_spawn_signal TERM; spawn_wait; _spawn_exit=$?; trap - EXIT; exit "$_spawn_exit"' EXIT
    _CODER_TRAPPED=1
  fi
  printf %s\\n "$_spawned"
  unset _bin _alive_pids _pid _spawned || true
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
          # Find the supervise.sh script
          _bindir=$(dirname "$0")
          for _d in share/orchestration ../share/orchestration; do
            if [ -d "${_bindir}/$_d" ]; then
              if [ -x "${_bindir}/$_d/supervise.sh" ]; then
                _supervise="${_bindir}/$_d/supervise.sh"
                break
              fi
            fi
          done
          [ -z "$_supervise" ] && error "Could not find supervise.sh!"
          debug "Using %s to supervise %s" "$_supervise" "$_script"
          "$_supervise" -n "$_s" -b "$_script" -- "$@" &
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
