#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
# shellcheck disable=SC3040 # ok, see: https://unix.stackexchange.com/a/654932
set -euo pipefail


# Container orchestrator to use. Default is to pick first of podman or docker.
: "${DEVENV_ORCHESTRATOR:=""}"

# Path to private SSH key to use for authentication, will be passed to
# container, together with public key. Default to best guess under .ssh
# directory.
: "${DEVENV_IDENTITY:=""}"

# Name of the container to use. When empty, will use the name of the volume or
# the directory name. Existing container under that name will be removed and
# (re-)created.
: "${DEVENV_NAME:=""}"

# Docker image to use
: "${DEVENV_IMAGE:="ghcr.io/efrecon/devenv-code-tunnel-alpine:main"}"

# Name of the tunnel to use.
: "${DEVENV_TUNNEL:=""}"

# Dry run mode, when set to 1, will not actually run the container, but
# instead print the command that would be run.
: "${DEVENV_DRY_RUN:=""}"

# Detach mode, when set to 1, will run the container in the background.
: "${DEVENV_DETACH:=""}"

info() {
  _fmt="$1"
  shift
  # shellcheck disable=SC2059 # ok, we want to use printf format
  printf "${_fmt}\n" "$@" >&2
}

error() {
  info "$@"
  exit 1
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [volume|directory] [--] [args...]
Options:
  -d          Detach mode, run the container in the background.
  -i <path>   Path to private SSH key to pass to container. Default to best guess from .ssh directory.
  -I <image>  Docker image to use. Default to latest full image.
  -n          Dry-run: just print the command that would be run, do not run it.
  -N <name>   Name of the container to use. Default based on volume or directory name mounted.
  -o <name>   Container orchestrator to use. Default picks first of podman or docker.
  -t <name>   Name of the tunnel to use. Default to hostname-containername.
  -h          Show this help message and exit.

First argument is the name of a volume or directory to share with the container.
If no volume or directory is given, the current directory will be used.
+ When a volume is given, it will be created if it does not exist.
+ When a directory is given, it will be mounted inside the container.

Everything else is passed to the container, as is.

Examples:
  $(basename "$0") devenv -v;  # Creates and use a devenv volume, passing -v to the container entrypoint.
  $(basename "$0") -- -v;      # Mount the current directory, passing -v to the container entrypoint.
EOF

  exit "${1:-0}"
}

while getopts "di:I:N:o:t:nh" opt; do
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
    t) # Name of the tunnel to use. Default to hostname-containername.
      DEVENV_TUNNEL="$OPTARG";;
    h) # Show help
      usage 0
      ;;
    *)  # Unknown option
      error "Unknown option: %s" "$opt"
      ;;
  esac
done
shift $((OPTIND - 1))

runif() {
  if [ -n "${DEVENV_DRY_RUN:-}" ] && [ "$DEVENV_DRY_RUN" = "1" ]; then
    if [ "$1" = "exec" ]; then
      # When running in dry-run mode, we don't want to run the command, but
      # rather print it.
      shift
    fi
    info "Dry-run mode, would run:: %s" "$*"
  else
    "$@"
  fi
}

# Pick container orchestrator. Default to podman, then docker. If neither is
# found, exit with error.
if command -v podman >/dev/null 2>&1; then
  DEVENV_ORCHESTRATOR=podman
elif command -v docker >/dev/null 2>&1; then
  DEVENV_ORCHESTRATOR=docker
else
  error "No container orchestrator found. Please install podman or docker."
fi

# Pick private SSH key to use. Default to best guess from .ssh directory. This
# sorts because we prefer ed25519 keys over rsa keys.
if [ -z "$DEVENV_IDENTITY" ]; then
  # shellcheck disable=SC2016 # ok, we want to use printf format
  DEVENV_IDENTITY=$(find "$HOME/.ssh" -type f -name 'id_*' | sort | head -n 1)
  if [ -z "$DEVENV_IDENTITY" ]; then
    error "No SSH key found. Please set DEVENV_IDENTITY or create an SSH key."
  else
    info "Using SSH key: %s" "$DEVENV_IDENTITY"
  fi
fi

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

# Shift over the double dash, if present.
[ -n "${1:-}" ] && [ "$1" = "--" ] && shift

# When no container name is given, use the name of the volume or the directory
# name.
if [ -z "$DEVENV_NAME" ]; then
  DEVENV_NAME=$(basename "$(realpath "$root")")
  info "Using container name: %s" "$DEVENV_NAME"
fi

# When no tunnel name is given, construct one based on the hostname and the name
# of the container to create. This should be more or less unique.
if [ -z "$DEVENV_TUNNEL" ]; then
  DEVENV_TUNNEL=$(hostname)-$DEVENV_NAME
  info "Using tunnel name: %s" "$DEVENV_TUNNEL"
fi

# Force pulling of the image, do this early so we can fail fast if the image
# cannot be pulled.
runif "$DEVENV_ORCHESTRATOR" image pull "$DEVENV_IMAGE" || \
  error "Failed to pull image: %s" "$DEVENV_IMAGE"

# Remove the container if it already exists.
if "$DEVENV_ORCHESTRATOR" container list -qa --filter name="$DEVENV_NAME" | grep -q .; then
  info "Container '%s' already exists, removing it." "$DEVENV_NAME"
  runif "$DEVENV_ORCHESTRATOR" container rm -f "$DEVENV_NAME" || \
    error "Failed to remove container: %s" "$DEVENV_NAME"
fi

# When using a volume, check if it exists. If not, create it.
if ! [ -d "$root" ]; then
  if ! "$DEVENV_ORCHESTRATOR" volume ls | grep -Fq "$root"; then
    runif "$DEVENV_ORCHESTRATOR" volume create "$root" || \
      error "Failed to create volume: %s" "$root"
  fi
fi

# Now start constructing the command to run. make sure what was left of the
# options/arguments that were passed to this script are passed to the container
# entrypoint.
set -- \
    --name "$DEVENV_NAME" \
    --hostname "$DEVENV_TUNNEL" \
    -v "$root:/home/coder:Z" \
    -v "$DEVENV_IDENTITY:/home/coder/.ssh/$(basename "$DEVENV_IDENTITY"):Z,ro" \
    -v "${DEVENV_IDENTITY}.pub:/home/coder/.ssh/$(basename "$DEVENV_IDENTITY").pub:Z,ro" \
    --privileged \
    "$DEVENV_IMAGE" \
      "$@"

# Detach or not. When not in detach mode, we will run the container in
# interactive mode, with a terminal attached, and remove the container when it
# exits.
if [ -n "${DEVENV_DETACH:-}" ] && [ "$DEVENV_DETACH" = "1" ]; then
  info "Starting container '%s' in background" "$DEVENV_NAME"
  set -- --restart unless-stopped -d "$@"
else
  info "Starting self-destructing container '%s' in foreground" "$DEVENV_NAME"
  set -- -it --rm "$@"
fi

# Tweak the command to run the container when using podman.
if [ "$DEVENV_ORCHESTRATOR" = "podman" ]; then
  set -- --userns=keep-id "$@"
fi
# Now finalize the command to start the container.
set -- "$DEVENV_ORCHESTRATOR" container run "$@"

# Replace the current shell with the command to run the container.
runif exec "$@"
