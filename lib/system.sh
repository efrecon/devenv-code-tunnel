#!/bin/sh

# Note: This is a library, not a standalone script. It is meant to be sourced
# from other scripts.

INSTALL_REPOS_SHA256=

# Check if a command is available. If not, print a warning and return 1.
check_command() {
  trace "Checking $1 is an accessible command"
  if ! command -v "$1" >/dev/null 2>&1; then
    warn "Command not found: %s" "$1"
    return 1
  fi
}

command_present() {
  if ! command -v "$1" >/dev/null 2>&1; then
    debug "Command not found: %s" "$1"
    return 1
  fi
}

# Run the command passed as arguments as root, i.e. with sudo if
# available/necessary. Generate an error if not possible.
as_root() {
  if [ "$(id -u)" = 0 ]; then
    "$@"
  elif command_present sudo; then
    debug "Running elevated command: %s" "$*"
    sudo "$@"
  else
    error "This script requires root privileges"
  fi
}


# Create a temporary script that will call the remaining of the arguments.
# This is because su is evil and -c option only takes a single command...
su_user() {
  _USR=$1; shift
  _tmpf=$(mktemp)
  printf '#!%s\n' "/bin/sh" > "$_tmpf"
  printf "exec" >> "$_tmpf"
  for a in "$@"; do
    [ -n "$a" ] && printf ' "%s"' "$a" >> "$_tmpf"
  done
  printf \\n >> "$_tmpf"
  chmod a+rx "$_tmpf"
  su -c "$_tmpf" "$_USR"
  rm -f "$_tmpf"
}

as_user() {
  USR=$(printf %s\\n "${1:-"${INSTALL_USER:-"$TUNNEL_USER"}"}" | cut -d: -f1)
  [ -z "$USR" ] && error "as_user: no user given"
  shift

  if [ "$(id -un)" = "$USR" ]; then
    "$@"
  elif command_present sudo; then
    sudo -u "$USR" -- "$@"
  elif command_present su; then
    su_user "$USR" "$@"
  else
    error "Cannot switch to user $USR: neither sudo nor su is available"
  fi
}


install_packages_alpine() {
  state=$(sha256sum "/etc/apk/repositories" | head -c 64)
  if [ "$state" != "$INSTALL_REPOS_SHA256" ]; then
    debug "Updating packages cache"
    as_root apk update -q
    INSTALL_REPOS_SHA256=$state
  fi
  verbose "Installing packages: $*"
  # shellcheck disable=SC2086 # We want to expand the arguments
  retry as_root ${INSTALL_OPTIMIZE:-} apk add --no-progress -q "$@"
}


install_packages_debian() {
  if [ "$(get_distro_name)" = "ubuntu" ]; then
    state=$(sha256sum "/etc/apt/sources.list" | head -c 64)
  elif [ "$(get_distro_name)" = "debian" ]; then
    state=$(sha256sum "/etc/apt/sources.list.d/debian.sources" | sha256sum | head -c 64)
  else
    error "Unsupported OS: %s" "$(get_distro_name)"
  fi
  if [ "$state" != "$INSTALL_REPOS_SHA256" ]; then
    # Avoid questons about interactive prompts
    # See: https://askubuntu.com/a/1036630
    DEBIAN_FRONTEND=noninteractive
    export DEBIAN_FRONTEND

    debug "Updating packages cache"
    as_root apt-get update -qq >/dev/null
    INSTALL_REPOS_SHA256=$state
  fi
  verbose "Installing packages: $*"
  # shellcheck disable=SC2086 # We want to expand the arguments
  as_root ${INSTALL_OPTIMIZE:-} apt-get install -y -qq "$@" >/dev/null
}


install_packages() {
  if is_os_family alpine; then
    install_packages_alpine "$@"
  elif is_os_family debian; then
    install_packages_debian "$@"
  else
    error "Unsupported OS family: %s" "$(get_distro_name)"
  fi
}


install_ondemand() {
  while read -r bin pkg; do
    [ -z "$pkg" ] && pkg=$bin
    if [ "${bin:-}" != "-" ] && ! command_present "${bin:-}"; then
      debug "$bin not found, installing $pkg"
      install_packages "$pkg"
    elif [ "${bin:-}" = "-" ] && [ -n "${pkg:-}" ]; then
      debug "Installing $pkg"
      install_packages "$pkg"
    fi
  done
}


install_clear_cache() {
  if is_os_family alpine; then
    as_root apk cache clean
    as_root rm -rf /var/cache/apk/*
  elif is_os_family debian; then
    as_root apt-get -y clean
    as_root apt-get -y autoremove
    as_root rm -rf /var/lib/apt/lists/*
  else
    error "Unsupported OS family: %s" "$(get_distro_name)"
  fi
  INSTALL_REPOS_SHA256=
}


make_owned_dir() {
  [ -z "${1:-}" ] && error "make_owned_dir: no dir given"
  if ! [ -d "$1" ]; then
    mkdir -p "$1"
  fi
  if [ -n "${2:-$INSTALL_USER}" ]; then
    chown -R "${2:-$INSTALL_USER}" "$1"
  fi
}


create_user() {
  NEW_USER=$(printf %s\\n "${1:-$INSTALL_USER}" | cut -d: -f1)
  if [ -n "${2:-}" ]; then
    NEW_GROUP=$2
  else
    # If no group is provided, use the second part of the INSTALL_USER. This
    # will be the same as the username when no colon is present.
    NEW_GROUP=$(printf %s\\n "${1:-$INSTALL_USER}" | cut -d: -f2)
  fi

  if grep -q "^$NEW_USER" /etc/passwd; then
    error "%s already exists!" "$NEW_USER"
  else
    if ! getent group "$NEW_GROUP" >/dev/null 2>&1; then
      # If the group does not exist, create it.
      debug "Creating group %s" "$NEW_GROUP"
      addgroup "$NEW_GROUP"
    fi
    if ! getent passwd "$NEW_USER" >/dev/null 2>&1; then
      # Pick a shell for the user.
      for shell in bash zsh ash dash sh; do
        if [ -x "/bin/$shell" ]; then
          SHELL="/bin/$shell"
          break
        fi
      done

      # Bail out when no shell is found.
      if [ -z "$SHELL" ]; then
        error "No shell found for user %s" "$NEW_USER"
      fi

      # If the user does not exist, create it.
      verbose "Creating user %s, using shell: %s" "$NEW_USER" "$SHELL"
      adduser \
        --disabled-password \
        --gecos "" \
        --shell "$SHELL" \
        --ingroup "$NEW_GROUP" \
        "$NEW_USER"
      # Unlock account and set an invalid password hash. See:
      # https://unix.stackexchange.com/a/750967
      printf '%s:*\n' "$NEW_USER" | chpasswd -e
    fi
  fi
}


home_dir() {
  USR=$(printf %s\\n "${1:-$INSTALL_USER}" | cut -d: -f1)
  HM=$(getent passwd "$USR" | cut -d: -f6)
  printf %s\\n "$HM"
}


user_local_dir() {
  if [ -d "$(home_dir "${1:-$INSTALL_USER}")" ]; then
    printf %s\\n "$(home_dir "${1:-$INSTALL_USER}")/.local"
  fi
}


xdg_user_dirs() {
  HM=$(home_dir "${1:-$INSTALL_USER}")
  if [ -d "$HM" ]; then
    LCL=$(user_local_dir "${1:-$INSTALL_USER}")
    make_owned_dir "$HM/.config" "${1:-$INSTALL_USER}"
    make_owned_dir "$HM/.cache" "${1:-$INSTALL_USER}"
    make_owned_dir "${LCL}/share" "${1:-$INSTALL_USER}"
    make_owned_dir "${LCL}/state" "${1:-$INSTALL_USER}"
    make_owned_dir "${LCL}/bin" "${1:-$INSTALL_USER}"
  else
    warn "Home directory $HM for user $USR does not exist!"
  fi
}


is_musl_os() {
  (ldd --version 2>&1 || true) | grep -q musl
}


get_arch() {
  arch=$(uname -m)
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "$arch" ]; then
      printf %s\\n "$2"
      return 0
    else
      shift 2
    fi
  done

  case "$arch" in
    x86_64) arch="x64" ;;
    i686) arch="x86" ;;
    i386) arch="x86" ;;
    aarch64) arch="arm64" ;;
    armv7l) arch="armhf" ;;
    armv6l) arch="armhf" ;;
    *) arch="$(uname -m)" ;;
  esac
  printf %s\\n "$arch"
}


get_golang_arch() {
  get_arch \
    x86_64 amd64 \
    i686 386 \
    aarch64 arm64 \
    armv7l arm \
    armv6l arm
}


get_os() {
  printf %s\\n "$(uname | to_lower)"
}

get_release_info() {
  grep -E -e "^${1}=" /etc/os-release | cut -d= -f2 | tr -d '"' | tr -d '\n'
}

get_distro_name() {
  get_release_info ID
}

get_distro_version() {
  get_release_info VERSION_ID
}

is_os_family() {
  [ -z "$1" ] && error "is_os_family: must pass family name, e.g. alpine, debian, etc."
  [ "$(get_distro_name)" = "$1" ] || get_release_info ID_LIKE | grep -q "$1"
}


# Print the item at the index at $1 of the remaining arguments. $1 is 0-indexed.
_index() {
  _idx=$1; shift
  shift "$_idx"
  printf %s\\n "$1"
}


# Non-entirely portable way to print all the descendants of the process which
# identifier is passed as a parameter. This uses the content of the /proc file
# system.
ps_children() (
  # This uses a () to force an extra process and have truly local vars.
  for _f in /proc/[0-9]*/stat; do
    # The name of the executable appears at the beginning between parenthesis.
    # Remove it.
    _stat=$(sed -E 's/\([^)]+\)\s//g' < "$_f")
    # If the parent process (3rd item) is the process passed as a parameter,
    # then we should count it.
    # shellcheck disable=SC2086 # We want to expand the arguments
    if [ "$(_index 2 $_stat)" = "$1" ]; then
      # The pid is also part of the stat file list, but also the name of the
      # directory. The following uses shell built-ins and is quicker.
      _pid=$(basename "$(dirname "$_f")")
      # Recurse first so we print the leaves first.
      ps_children "$_pid"
      printf %d\\n "$_pid"
    fi
  done
)

kill_tree() {
  [ -z "${1:-}" ] && error "kill_tree: must pass pid as first arg"
  for _pid in $(ps_children "$1"); do
    kill -"${2:-TERM}" "$_pid"
  done
  kill -"${2:-TERM}" "$1"
}
