#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
set -eu
# shellcheck disable=SC3040 # POSIX now, but not in all shells yet
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Container orchestrator to use. Default is to pick first of msb, podman or docker.
: "${DEVENV_ORCHESTRATOR:=""}"

# Path to private SSH key to use for authentication, will be passed to
# container, together with public key. Default to best guess under .ssh
# directory. Set to "-" to not pass any key.
: "${DEVENV_IDENTITY:=""}"

# GitHub token to pass to the environment, or path to a file containing the
# token. Default to the token of the gh CLI, when logged in. Set to "-" to not
# pass any token.
: "${DEVENV_GITHUB_TOKEN:=""}"

# Directory where to store GitHub tokens before they are mounted into the
# environments, one sub-directory per environment.
: "${DEVENV_STATE_DIR:="${XDG_STATE_HOME:-"$HOME/.local/state"}/devenv"}"

# Name of the container to use. When empty, will use the name of the volume or
# the directory name. Existing container under that name will be removed and
# (re-)created.
: "${DEVENV_NAME:=""}"

# Docker image to use
: "${DEVENV_IMAGE:="ghcr.io/efrecon/devenv-code-tunnel-alpine:main"}"

# Name of the tunnel to use.
: "${DEVENV_TUNNEL:=""}"

# Runtime to use for the container. When empty, will use default runtime,
# preferably krun.
: "${DEVENV_RUNTIME:=""}"

# Dry run mode, when set to 1, will not actually run the container, but
# instead print the command that would be run.
: "${DEVENV_DRY_RUN:=0}"

# Detach mode, when set to 1, will run the container in the background.
: "${DEVENV_DETACH:=0}"

# Default XDG config directory.
: "${XDG_CONFIG_HOME:="$HOME/.config"}"

# Colon-separated directories where to look for env files
: "${DEVENV_PATH:="/etc:/usr/local/etc:$XDG_CONFIG_HOME:$HOME"}"

# space-separated names of the env files to look for in each directory. Order
# kind of matters: hidden files for "secret settings" should come last and
# override.
: "${DEVENV_ENVFILES:="devenv.env .devenv.env"}"

# Verbosity level for this script.
: "${DEVENV_VERBOSE:=1}"

# Maximum tunnel name size
: "${DEVENV_TUNNEL_NAME_MAX_SIZE:=20}"

# Additional options to pass to the container runner.
: "${DEVENV_OPTIONS:=""}"

# Sanitize who we are, handle curl|(ba)sh case.
DEVENV_BIN=$(basename "$0")
[ -z "$DEVENV_BIN" ] && DEVENV_BIN="devenv.sh"
printf '%s\n' "$DEVENV_BIN" | grep -qE '^[a-z]*sh$' && DEVENV_BIN="devenv.sh"


usage() {
  cat <<EOF
Usage: $DEVENV_BIN [options] [volume|directory] [--] [args...]
Options:
  -d          Detach mode, run the container in the background.
  -i <path>   Path to private SSH key to pass to container. Default: best guess from .ssh directory. For no key, use "-".
  -I <image>  Docker image to use. Default to latest full image.
  -n          Dry-run: just print the command that would be run, do not run it.
  -N <name>   Name of the container to use. Default based on volume or directory name mounted.
  -o <name>   Container orchestrator to use. Default picks first of msb, podman or docker.
  -r <name>   Container runtime to use, default is to prefer krun on podman, when possible.
  -t <name>   Name of the tunnel to use. Default to hostname-containername.
  -T <token>  GitHub token, or path to file with token, to pass to container. Default: from gh CLI, when logged in. For no token, use "-".
  -v          Increase verbosity level. Can be used multiple times.
  -h          Show this help message and exit.
  --opt <val> Pass additional options to the container runner, blindly.

First argument is the name of a volume or directory to share with the container.
If no volume or directory is given, the current directory will be used.
-  When a volume is given, it will be created if it does not exist.
-  When a directory is given, it will be mounted inside the container.

Everything else is passed to the container, as is.

All files named after $DEVENV_ENVFILES in directories from $DEVENV_PATH are read,
in order, before parsing the options. They contain KEY=VALUE lines, values are
never evaluated. Only DEVENV_ and TUNNEL_ variables are recognised, variables
already in the environment take precedence. DEVENV_PATH and DEVENV_ENVFILES can
only be set from the environment.
Set DEVENV_ or TUNNEL_ variables to set defaults for $DEVENV_BIN or the container entrypoint.

Examples:
  $DEVENV_BIN devenv -v;  # Creates and use a devenv volume, passing -v to the container entrypoint.
  $DEVENV_BIN -- -v;      # Mount the current directory, passing -v to the container entrypoint.
EOF

  exit "${1:-0}"
}


# Main entry point, called at the very end of this script so all functions are
# defined by then, and so that a truncated download (curl|sh) runs nothing.
main() {
  # Read all env files with names from the space-separated DEVENV_ENVFILES, found
  # in the directories of the colon-separated DEVENV_PATH. Files are read in
  # order, so later files override settings from earlier ones. Variables
  # already in the environment take precedence: remember their names first.
  _env_names=" $(env | { grep -oE '^(DEVENV|TUNNEL)_[A-Za-z0-9_]*=' || true; } | tr -d = | tr '\n' ' ')"
  _ifs=$IFS; IFS=:
  for _env_dir in $DEVENV_PATH; do
    [ -d "$_env_dir" ] || continue
    IFS=$_ifs
    for _env_name in $DEVENV_ENVFILES; do
      if [ -f "${_env_dir%/}/$_env_name" ]; then
        info "Reading env file: %s" "${_env_dir%/}/$_env_name"
        env_load "${_env_dir%/}/$_env_name";  # Sets DEVENV_ and TUNNEL_ variables
      fi
    done
    IFS=:
  done
  IFS=$_ifs
  unset _ifs _env_dir _env_name _env_names

  # Now parse the options. Do it here so we can override the defaults set by the
  # env files or environment variables.
  while [ $# -gt 0 ]; do
    OPTIND=1
    while getopts ":di:I:N:o:t:T:r:nvh-:" opt; do
      case "$opt" in
        d) # Detach mode, run the container in the background.
          DEVENV_DETACH=1;;
        i) # Path to private SSH key to pass to container. Default to best guess from .ssh directory
          DEVENV_IDENTITY="$OPTARG";;
        I) # Docker image to use. Default to latest full image.
          DEVENV_IMAGE="$OPTARG";;
        n) # Dry-run: just print the command that would be run, do not run it.
          DEVENV_DRY_RUN=1;;
        N) # Name of the container to use. Default based on volume or directory name mounted.
          DEVENV_NAME="$OPTARG";;
        o) # Container orchestrator to use. Default picks first of podman or docker.
          DEVENV_ORCHESTRATOR="$OPTARG";;
        r) # Runtime to use for the container. Default to krun, if available.
          DEVENV_RUNTIME="$OPTARG";;
        t) # Name of the tunnel to use. Default to hostname-containername.
          DEVENV_TUNNEL="$OPTARG";;
        T) # GitHub token, or path to file with token. Default to token from gh CLI
          DEVENV_GITHUB_TOKEN="$OPTARG";;
        v) # Increase verbosity level. Can be used multiple times.
          DEVENV_VERBOSE=$((DEVENV_VERBOSE + 1));;
        h) # Show help
          usage 0
          ;;
        -) # Save any option starting with -- and its value
          case "$OPTARG" in
            *=*)
              _entry="--$OPTARG"
              ;;
            *)
              _entry="--$OPTARG"
              if [ "$OPTIND" -le "$#" ]; then
                _val=
                eval "_val=\${$OPTIND}"
                case "$_val" in
                  -*)
                    ;;
                  *)
                    _entry="$_entry $_val"
                    shift "$OPTIND"
                    OPTIND=1
                    [ -z "$DEVENV_OPTIONS" ] && DEVENV_OPTIONS="$_entry" || DEVENV_OPTIONS="$DEVENV_OPTIONS $_entry"
                    continue 2
                    ;;
                esac
              fi
              ;;
          esac
          [ -z "$DEVENV_OPTIONS" ] && DEVENV_OPTIONS="$_entry" || DEVENV_OPTIONS="$DEVENV_OPTIONS $_entry"
          ;;
        *)  # Unknown option
          usage 1
          ;;
      esac
    done
    shift $((OPTIND - 1))
    break
  done
  unset _entry _val

  # Pick the orchestrator to use based on availability and user preference
  orchestrator_pick;  # Sets DEVENV_ORCHESTRATOR

  # Determine the sandboxing mode based on the orchestrator. Used both for
  # logging and for actual runtime behavior.
  DEVENV_SANDBOXING=Container
  [ "$DEVENV_ORCHESTRATOR" = "msb" ] && DEVENV_SANDBOXING=Sandbox
  DEVENV_SANDBOXING_LCASE=$(printf "%s" "$DEVENV_SANDBOXING" | tr '[:upper:]' '[:lower:]')

  # Pick authentication credentials for GitHub and identity.
  github_token_pick;  # Sets DEVENV_GITHUB_TOKEN
  identity_pick;      # Sets DEVENV_IDENTITY

  # Handle remaining arguments. The first argument is the name of a volume, or the
  # path to a directory to mount inside the container. When this is empty, or not
  # provided -- the first argument starts with a dash, then the current directory
  # is mounted. Shift over the first argument, whenever applicable, so all
  # remaining arguments are passed to the image entrypoint. Recognize the special
  # -- case along the way.
  if [ "$#" -eq 0 ]; then
    info "No arguments given, will share the current directory."
  fi

  if [ "$#" -gt 0 ]; then
    if [ "${1#-}" != "$1" ]; then
      # First argument is an option, so we don't use it as the root
      # directory/volume name.
      root="$(pwd)"
    elif [ -n "$1" ]; then
      # We had a first argument, use it as the root (can be a volume or a
      # directory)
      root=$1
      shift
    else
      # The first argument was empty, use the current directory.
      root="$(pwd)"
      shift
    fi
  else
    root="$(pwd)"
  fi

  # Orchestrators take relative paths without a leading / for volume names: pass
  # directories with their full path to mount them. Physical path (-P), as
  # mounting through symlinks is not portable.
  if [ -d "$root" ]; then
    root=$(cd -P -- "$root" && pwd -P) || error "Cannot resolve directory: %s" "$root"
  fi

  # Shift over the double dash, if present.
  [ -n "${1:-}" ] && [ "$1" = "--" ] && shift

  name_pick "$root";  # Sets DEVENV_NAME
  tunnel_pick;        # Sets DEVENV_TUNNEL

  # Force pulling of the image, do this early so we can fail fast if the image
  # cannot be pulled.
  if ! printf %s\\n "$DEVENV_IMAGE" | grep -qE '^localhost/'; then
    runif "$DEVENV_ORCHESTRATOR" image pull "$DEVENV_IMAGE" || \
      error "Failed to pull image: %s" "$DEVENV_IMAGE"
  fi

  # Remove the devenv runtime (container, sandbox) if it already exists.
  if runtime_exists "$DEVENV_NAME"; then
    info "%s '%s' already exists, removing it." "$DEVENV_SANDBOXING" "$DEVENV_NAME"
    runif "$DEVENV_ORCHESTRATOR" "$DEVENV_SANDBOXING_LCASE" rm -f "$DEVENV_NAME" || \
      error "Failed to remove %s: %s" "$DEVENV_SANDBOXING_LCASE" "$DEVENV_NAME"
  fi

  # When using a volume, check if it exists. If not, create it.
  if ! [ -d "$root" ]; then
    if ! "$DEVENV_ORCHESTRATOR" volume ls | grep -qF "$root"; then
      runif "$DEVENV_ORCHESTRATOR" volume create "$root" || \
        error "Failed to create volume: %s" "$root"
    fi
  fi

  # Pass the GitHub token to the container by storing it in a file.
  github_token_store;  # Sets DEVENV_GITHUB_TOKEN_FILE

  # Now start constructing the command to run. make sure what was left of the
  # options/arguments that were passed to this script are passed to the container
  # entrypoint.
  if [ "$DEVENV_ORCHESTRATOR" = "msb" ]; then
    MOUNT_OPTS="uid=1000,gid=1000"
    # msb requires an explicit -- between the image and the command arguments.
    set -- \
        -v "$root:/home/coder:$MOUNT_OPTS" \
        "$DEVENV_IMAGE" \
          -- "$@"
  else
    MOUNT_OPTS="Z"
    set -- \
        -v "$root:/home/coder:$MOUNT_OPTS" \
        "$DEVENV_IMAGE" \
          "$@"
  fi

  # Mount the GitHub token where the entrypoint expects it by default, i.e.
  # TUNNEL_GITHUB_TOKEN_FILE.
  if [ -n "$DEVENV_GITHUB_TOKEN_FILE" ]; then
    set -- \
      -v "$DEVENV_GITHUB_TOKEN_FILE:/run/secrets/github-token:$MOUNT_OPTS,ro" \
      "$@"
  fi

  if [ -n "$DEVENV_IDENTITY" ]; then
    set -- \
      -v "$DEVENV_IDENTITY:/home/coder/.ssh/$(basename "$DEVENV_IDENTITY"):$MOUNT_OPTS,ro" \
      -v "${DEVENV_IDENTITY}.pub:/home/coder/.ssh/$(basename "$DEVENV_IDENTITY").pub:$MOUNT_OPTS,ro" \
      "$@"
  fi

  set -- \
      --name "$DEVENV_NAME" \
      --hostname "$DEVENV_TUNNEL" \
        "$@"

  # Detach or not. When not in detach mode, we will run the container in
  # interactive mode, with a terminal attached, and remove the container when it
  # exits.
  if [ "$DEVENV_DETACH" = "1" ]; then
    info "Starting %s '%s' in background" "$DEVENV_SANDBOXING_LCASE" "$DEVENV_NAME"
    if [ "$DEVENV_ORCHESTRATOR" = "msb" ]; then
      set -- -d "$@"
    else
      set -- --restart unless-stopped -d "$@"
    fi
  else
    info "Starting self-destructing %s '%s' in foreground" "$DEVENV_SANDBOXING_LCASE" "$DEVENV_NAME"
    if [ "$DEVENV_ORCHESTRATOR" = "msb" ]; then
      set -- -t "$@"
    else
      if [ -t 0 ]; then
        set -- -it --rm "$@"
      else
        set -- -t --rm "$@"
      fi
    fi
  fi

  # Tweak the command to run the container when using podman.
  if [ "$DEVENV_ORCHESTRATOR" = "podman" ]; then
    set -- --userns=keep-id:uid=1000,gid=1000 "$@"
    if [ -z "$DEVENV_RUNTIME" ] && command -v krun >/dev/null 2>&1; then
      DEVENV_RUNTIME=krun
    fi
    if [ "${DEVENV_RUNTIME:-}" = "krun" ]; then
      # When using krun, it is not possible to use the QUIC protocol (on top of
      # UDP) for cloudflare tunnels. Force running on top of HTTP/2.
      set -- --runtime=krun --user 0:0 -e TUNNEL_CLOUDFLARE_PROTOCOL=http2 -e TUNNEL_DOCKERD_OPTIONS="--firewall-backend=nftables --ip-forward=false" "$@"
    elif [ -n "$DEVENV_RUNTIME" ]; then
      set -- --runtime="$DEVENV_RUNTIME" --privileged "$@"
    else
      set -- --privileged "$@"
    fi
  elif [ "$DEVENV_ORCHESTRATOR" = "docker" ]; then
    if [ -n "$DEVENV_RUNTIME" ]; then
      set -- --runtime="$DEVENV_RUNTIME" --privileged "$@"
    else
      set -- --privileged "$@"
    fi
  fi

  # Pass all variables starting with TUNNEL_ to the container.
  for _env in $(env | grep -E '^TUNNEL_' | cut -d= -f1); do
    set -- -e "$_env" "$@"
  done

  # Now finalize the command to start the container.
  # shellcheck disable=SC2086 # We want word splitting for DEVENV_OPTIONS
  set -- "$DEVENV_ORCHESTRATOR" "$DEVENV_SANDBOXING_LCASE" run $DEVENV_OPTIONS "$@"

  # Replace the current shell with the command to run the container.
  runif exec "$@"
}



# PML: Poor Man's Logging on stderr
_log() {
  printf '[%s] [%s] [%s] ' \
    "$DEVENV_BIN" \
    "${1:-LOG}" \
    "$(date +'%Y%m%d-%H%M%S')" \
    >&2
  shift
  _fmt="$1"
  shift
  # shellcheck disable=SC2059 # ok, we want to use printf format
  printf "${_fmt}\n" "$@" >&2
}
trace() { [ "$DEVENV_VERBOSE" -ge "2" ] && _log DBG "$@" || true ; }
info() { [ "$DEVENV_VERBOSE" -ge "1" ] && _log NFO "$@" || true ; }
warn() { _log WRN "$@"; }
error() { _log ERR "$@" && exit 1; }


# Read the env file at $1, made of KEY=VALUE lines. Blank lines, comments and an
# optional leading "export" are allowed. Values can be single- or double-quoted,
# unquoted values end at a whitespace-preceded #. Values are never evaluated.
# Only DEVENV_ and TUNNEL_ variables are set, except DEVENV_PATH and
# DEVENV_ENVFILES, and except those which names are in $_env_names, i.e. already
# in the environment. TUNNEL_ variables are exported so they can be passed to
# the container, DEVENV_ variables stay local.
# shellcheck disable=SC2094 # $1 is only mentioned in logs, never written to
env_load() {
  _cr=$(printf '\r')
  _lineno=0
  while IFS= read -r _line || [ -n "$_line" ]; do
    _lineno=$((_lineno + 1))
    # Remove DOS line endings and leading whitespace.
    _line=${_line%"$_cr"}
    _line=${_line#"${_line%%[![:space:]]*}"}
    case "$_line" in
      ""|"#"*) continue;;
      export[[:space:]]*)
        _line=${_line#export}
        _line=${_line#"${_line%%[![:space:]]*}"}
        ;;
    esac
    case "$_line" in
      *=*) ;;
      *) warn "%s:%d: Not a KEY=VALUE line, ignored" "$1" "$_lineno"; continue;;
    esac

    _name=${_line%%=*}
    _name=${_name%"${_name##*[![:space:]]}"}
    case "$_name" in
      *[!A-Za-z0-9_]*)
        warn "%s:%d: Invalid variable name %s, ignored" "$1" "$_lineno" "$_name"; continue;;
      DEVENV_PATH|DEVENV_ENVFILES)
        warn "%s:%d: %s can only be set from the environment, ignored" "$1" "$_lineno" "$_name"; continue;;
      DEVENV_*|TUNNEL_*) ;;
      *)
        warn "%s:%d: %s is neither DEVENV_ nor TUNNEL_, ignored" "$1" "$_lineno" "$_name"; continue;;
    esac

    case "$_env_names" in
      *" $_name "*)
        trace "%s:%d: %s already set in environment, ignored" "$1" "$_lineno" "$_name"; continue;;
    esac

    _value=${_line#*=}
    _value=${_value#"${_value%%[![:space:]]*}"}
    case "$_value" in
      \"*) _value=${_value#\"}; _value=${_value%%\"*};;
      \'*) _value=${_value#\'}; _value=${_value%%\'*};;
      *)
        # Strip comments before trimming, as "KEY= # comment" is an empty value.
        _value=${_line#*=}
        _value=${_value%%[[:space:]]#*}
        _value=${_value#"${_value%%[![:space:]]*}"}
        _value=${_value%"${_value##*[![:space:]]}"}
        ;;
    esac

    trace "%s:%d: Setting %s" "$1" "$_lineno" "$_name"
    case "$_name" in
      TUNNEL_*) export "$_name=$_value";;
      # Safe: $_name is validated above, and $_value is not expanded by eval.
      *) eval "$_name=\$_value";;
    esac
  done < "$1"
  unset _cr _lineno _line _name _value
}


runif() {
  if [ "$DEVENV_DRY_RUN" = "1" ]; then
    if [ "$1" = "exec" ]; then
      # When running in dry-run mode, we don't want to run the command, but
      # rather print it.
      shift
    fi
    info "Dry-run mode, would run: %s" "$*"
  else
    "$@"
  fi
}


# Check if a runtime (container, sandbox) with the name passed as a parameter
# exists.
runtime_exists() {
  if [ "$DEVENV_ORCHESTRATOR" = "msb" ]; then
    "$DEVENV_ORCHESTRATOR" ps -qa | grep -qxF "$1" >/dev/null 2>&1
  else
    [ -n "$("$DEVENV_ORCHESTRATOR" ps -qa --filter "name=^/?${1}\$" 2>/dev/null)" ]
  fi
}


# Pick container orchestrator into DEVENV_ORCHESTRATOR. Default to msb, then
# podman, then docker. If none is found, or the one requested is not installed,
# exit with error.
orchestrator_pick() {
  if [ -z "$DEVENV_ORCHESTRATOR" ]; then
    if command -v msb >/dev/null 2>&1; then
      DEVENV_ORCHESTRATOR=msb
    elif command -v podman >/dev/null 2>&1; then
      DEVENV_ORCHESTRATOR=podman
    elif command -v docker >/dev/null 2>&1; then
      DEVENV_ORCHESTRATOR=docker
    else
      error "No orchestrator found. Please install msb, podman or docker."
    fi
  else
    if ! command -v "$DEVENV_ORCHESTRATOR" >/dev/null 2>&1; then
      error "Orchestrator not found: %s" "$DEVENV_ORCHESTRATOR"
    fi
  fi
}


# Pick GitHub token to use into DEVENV_GITHUB_TOKEN. Default to the token of the
# gh CLI, when installed and logged in at github.com.
github_token_pick() {
  if [ -z "$DEVENV_GITHUB_TOKEN" ]; then
    if command -v gh >/dev/null 2>&1; then
      DEVENV_GITHUB_TOKEN=$(gh auth token --hostname github.com 2>/dev/null || true)
      if [ -z "$DEVENV_GITHUB_TOKEN" ]; then
        warn "gh CLI is not logged in at github.com, will not forward a GitHub token."
      else
        info "Using GitHub token from gh CLI"
      fi
    else
      info "No gh CLI found, will not forward a GitHub token."
    fi
  fi
  # When token is set to "-", unset it to avoid passing any token, including a
  # TUNNEL_GITHUB_TOKEN that would otherwise be passed through the environment.
  if [ "$DEVENV_GITHUB_TOKEN" = "-" ]; then
    DEVENV_GITHUB_TOKEN=
    unset TUNNEL_GITHUB_TOKEN
  fi
  # Tokens never contain slashes, so this is a path to a file that should exist.
  if [ -n "$DEVENV_GITHUB_TOKEN" ] && ! [ -f "$DEVENV_GITHUB_TOKEN" ]; then
    case "$DEVENV_GITHUB_TOKEN" in
      */*) error "GitHub token file not found: %s" "$DEVENV_GITHUB_TOKEN";;
    esac
  fi
}


# Pick private SSH key to use into DEVENV_IDENTITY. Default to best guess from
# .ssh directory. This sorts because we prefer ed25519 keys over rsa keys.
identity_pick() {
  if [ -z "$DEVENV_IDENTITY" ]; then
    if [ -d "$HOME/.ssh" ]; then
      # shellcheck disable=SC2016 # ok, we want to use printf format
      DEVENV_IDENTITY=$(find "$HOME/.ssh" -type f -name 'id_*' | sort | head -n 1)
      if [ -z "$DEVENV_IDENTITY" ]; then
        warn "No SSH key found under %s, will not forward your identity." "$HOME/.ssh"
      else
        info "Using SSH key: %s" "$DEVENV_IDENTITY"
      fi
    else
      warn "No .ssh directory found under %s, will not forward your identity." "$HOME"
    fi
  fi
  # When identity is set to "-", unset it to avoid passing any key.
  [ "$DEVENV_IDENTITY" = "-" ] && DEVENV_IDENTITY=
  # Validate SSH key files exist
  if [ -n "$DEVENV_IDENTITY" ]; then
    if ! [ -f "$DEVENV_IDENTITY" ]; then
      error "Private SSH key file not found: %s" "$DEVENV_IDENTITY"
    fi
    if ! [ -f "${DEVENV_IDENTITY}.pub" ]; then
      error "Public SSH key file not found: %s" "${DEVENV_IDENTITY}.pub"
    fi
  fi
}


# Pick the name of the container into DEVENV_NAME. When no container name is
# given, use the name of the volume or the directory passed as $1.
name_pick() {
  if [ -z "$DEVENV_NAME" ]; then
    # Some realpath implementations fail on volume names, i.e. non-existing paths.
    DEVENV_NAME=$(basename "$(realpath "$1" 2>/dev/null || printf %s "$1")")
    info "Using %s name: %s" "$DEVENV_SANDBOXING_LCASE" "$DEVENV_NAME"
  fi
}


# Pick the name of the tunnel into DEVENV_TUNNEL. When no tunnel name is given,
# construct one based on the hostname and the name of the container to create.
# This should be more or less unique. Truncate to DEVENV_TUNNEL_NAME_MAX_SIZE.
tunnel_pick() {
  if [ -z "$DEVENV_TUNNEL" ]; then
    DEVENV_TUNNEL=$(hostname|cut -d. -f1)-$DEVENV_NAME
  fi
  if [ "$(printf %s "$DEVENV_TUNNEL" | wc -c)" -gt "$DEVENV_TUNNEL_NAME_MAX_SIZE" ]; then
    DEVENV_TUNNEL=$(
        printf %s "$DEVENV_TUNNEL" |
        cut -c1-$((DEVENV_TUNNEL_NAME_MAX_SIZE - 6))
      )-$(
        printf %s "$DEVENV_TUNNEL" |
        md5sum |
        cut -c1-5
      )
    warn "Truncated tunnel name to fit tunnel name size limit: %s" "$DEVENV_TUNNEL"
  fi
  info "Using tunnel name: %s" "$DEVENV_TUNNEL"
}


# Arrange for the GitHub token to be in a file that can be mounted into the
# environment, path in DEVENV_GITHUB_TOKEN_FILE. Tokens given as values are
# stored under the state directory, readable by the current user only. Using a
# file rather than an environment variable keeps the token out of the output of
# inspect commands.
github_token_store() {
  DEVENV_GITHUB_TOKEN_FILE=
  if [ -n "$DEVENV_GITHUB_TOKEN" ]; then
    if [ -f "$DEVENV_GITHUB_TOKEN" ]; then
      DEVENV_GITHUB_TOKEN_FILE=$(realpath "$DEVENV_GITHUB_TOKEN")
    else
      DEVENV_GITHUB_TOKEN_FILE=${DEVENV_STATE_DIR%/}/${DEVENV_NAME}/github-token
      if [ "$DEVENV_DRY_RUN" = "1" ]; then
        info "Dry-run mode, would store GitHub token in: %s" "$DEVENV_GITHUB_TOKEN_FILE"
      else
        (
          umask 077
          mkdir -p "$(dirname "$DEVENV_GITHUB_TOKEN_FILE")"
          printf '%s\n' "$DEVENV_GITHUB_TOKEN" > "$DEVENV_GITHUB_TOKEN_FILE"
        ) || error "Failed to store GitHub token in: %s" "$DEVENV_GITHUB_TOKEN_FILE"
        chmod 600 "$DEVENV_GITHUB_TOKEN_FILE"
        trace "Stored GitHub token in: %s" "$DEVENV_GITHUB_TOKEN_FILE"
      fi
    fi
  fi
}


# Last, so nothing runs until the whole script is downloaded (curl|sh).
main "$@"
