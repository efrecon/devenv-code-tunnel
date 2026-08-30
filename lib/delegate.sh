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


# Catch up the list of PIDs in _CODER_PIDS, removing any that have exited, add
# the ones passed as arguments if they are alive.
_spawn_update() {
  # Reconstruct the list of alive PIDs, by checking each PID in _CODER_PIDS. Any
  # PID passed as argument is to be added to the list, if it is alive.
  _alive_pids=
  for _pid in $_CODER_PIDS "$@"; do
    [ -z "${_pid:-}" ] && continue
    if kill -0 "$_pid" 2>/dev/null; then
      if [ -z "$_alive_pids" ]; then
        _alive_pids="$_pid"
      else
        _alive_pids="$_alive_pids $_pid"
      fi
    fi
  done
  _CODER_PIDS=$_alive_pids
  unset _alive_pids _pid || true
}


# Wait for the process with PID passed as $1 to exit. Returns the exit code of
# the process, or 0 if the process was already dead.
_spawn_wait() {
  [ -z "${1:-}" ] && return 0

  # Re-enter wait if interrupted by a signal before the process actually exits
  while kill -0 "$1" 2>/dev/null; do
    wait "$1" 2>/dev/null
    _wrc=$?
    if [ "$_wrc" -le 127 ]; then
      return "$_wrc"
    fi
  done

  return 0
}


# Wait for the processes with PIDs passed as arguments to exit. If no arguments
# are passed, wait for all PIDs in _CODER_PIDS. Returns the exit of the last
# process returning an error.
spawn_wait() {
  _ret=0

  # Decide upon the list of PIDs to wait for.
  _wait_pids=
  if [ "$#" -gt 0 ]; then
    _wait_pids="$*"
  else
    _wait_pids=$_CODER_PIDS
  fi

  # Wait in turns, remember last non-zero exit code.
  for _pid in $_wait_pids; do
    _spawn_wait "$_pid"
    _wrc=$?
    [ "$_wrc" -ne 0 ] && _ret=$_wrc
  done

  # Keep only processes that are still running.
  _spawn_update

  # Log and return the exit code of the last process that returned an error, if
  # any.
  [ -n "$_wait_pids" ] && debug "Spawned processes %s exited, returning %d" "$_wait_pids" "$_ret"
  unset _pid _wait_pids _wrc || true
  return "$_ret"
}


# Return the PID of the latest spawned process, or nothing if none are running.
spawn_latest() {
  printf '%s' "${_CODER_PIDS:-}" | tr ' ' '\n' | tail -n 1
}


# Send a signal to the process tree of each PID passed as argument, or to all
# PIDs in _CODER_PIDS if no arguments are passed. The signal to send is from the
# -s option, defaults to TERM.
spawn_kill() {
  _sigspec=TERM
  _tree=0
  _reason=unknown
  while getopts "r:s:t-" opt; do
    case "$opt" in
      r) # Specify the reason for logging purposes
        _reason=$OPTARG;;
      s) # Specify the sigspec
        _sigspec=$OPTARG;;
      t) # Specify whether to kill the process tree
        _tree=1;;
      -) # End of options, file name to follow
        break;;
      *)  # Unknown option
        error "spawn_kill: Unknown option $opt";;
    esac
  done
  shift $((OPTIND - 1))

  # Decide upon the list of PIDs to kill.
  _kill_pids=
  if [ "$#" -gt 0 ]; then
    _kill_pids="$*"
  else
    _kill_pids=$_CODER_PIDS
  fi

  # Kill the processes, or their trees.
  for _pid in $_kill_pids; do
    if [ "$_tree" -eq 1 ]; then
      debug "Killing tree of PID %d with signal %s. Reason: %s" "$_pid" "$_sigspec" "$_reason"
      kill_tree "$_pid" "$_sigspec" >/dev/null
    else
      debug "Killing PID %d with signal %s. Reason: %s" "$_pid" "$_sigspec" "$_reason"
      kill "-$_sigspec" "$_pid" 2>/dev/null || true
    fi
  done

  # Recapture the list of alive PIDs, since some may have exited.
  _spawn_update
  unset _pid _kill_pids _sigspec _tree || true
}


# Spawn a process in the background, and return its PID.
spawn() {
  _name=
  while getopts "n:-" opt; do
    case "$opt" in
      n) # Specify the name for logging purposes
        _name=$OPTARG;;
      -) # End of options, file name to follow
        break;;
      *)  # Unknown option
        error "spawn: Unknown option $opt";;
    esac
  done
  shift $((OPTIND - 1))

  # Sanity check on the executable.
  [ -z "${1:-}" ] && error "spawn: No executable given"
  [ -x "$1" ] || error "spawn: $1 is not executable"

  # Capture the executable and default name for logging purposes, if not already
  # set.
  _bin=$1
  shift
  [ -z "${_name:-}" ] && _name=$(basename "$_bin")

  # Spawn the process in the background, and remember its PID.
  trace "Spawning %s with arguments: %s" "$_bin" "$*"
  "$_bin" "$@" &
  _spawned=$!

  # Prune dead PIDs before appending, so the list only holds live processes. Add
  # the new PID to the list of live processes.
  _spawn_update "$_spawned"
  debug "Spawned %s with PID %d" "$_name" "$_spawned"

  # Install process-wide signal handlers if not already done.
  if [ "$_CODER_TRAPPED" = "0" ]; then
    trap 'spawn_kill -s HUP -r "HUP trap";  trap - HUP;  kill -HUP  $$' HUP
    trap 'spawn_kill -s INT -r "INT trap";  trap - INT;  kill -INT  $$' INT
    trap 'spawn_kill -s TERM -r "TERM trap"; spawn_wait || true; trap - TERM; kill -TERM $$' TERM
    # shellcheck disable=SC2154 # _spawn_exit set inside trap
    trap '_spawn_exit=$?; spawn_kill -s TERM -r "EXIT trap" || true; spawn_wait || true; trap - EXIT; exit "$_spawn_exit"' EXIT
    _CODER_TRAPPED=1
  fi

  # Return the PID of the spawned process, for convenience.
  printf %s\\n "$_spawned"
  unset _bin _name _spawned || true
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
