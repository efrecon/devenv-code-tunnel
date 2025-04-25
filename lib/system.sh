#!/bin/sh

# Note: This is a library, not a standalone script. It is meant to be sourced
# from other scripts.

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


as_user() {
  USR=$(printf %s\\n "${1:-$INSTALL_USER}" | cut -d: -f1)
  shift

  if [ "$(id -un)" = "$USR" ]; then
    "$@"
  elif check_command sudo; then
    sudo -u "$USR" -- "$@"
  elif check_command su; then
    # Create a temporary script that will call the remaining of the arguments.
    # This is because su is evil and -c option only takes a single command...
    tmpf=$(mktemp)
    printf '#!%s\n' "/bin/sh" > "$tmpf"
    printf "exec" >> "$tmpf"
    for a in "$@"; do
      [ -n "$a" ] && printf ' "%s"' "$a" >> "$tmpf"
    done
    printf \\n >> "$tmpf"
    chmod a+rx "$tmpf"
    su -c "$tmpf" "$USR"
    rm -f "$tmpf"
  else
    "$@"
  fi
}


install_packages() {
  state=$(sha256sum "/etc/apk/repositories" | head -c 64)
  if [ "$state" != "$INSTALL_REPOS_SHA256" ]; then
    verbose "Updating packages cache"
    as_root apk update
    INSTALL_REPOS_SHA256=$state
  fi
  verbose "Installing packages: $*"
  # shellcheck disable=SC2086 # We want to expand the arguments
  as_root ${INSTALL_OPTIMIZE:-} apk add "$@"
}


install_ondemand() {
  while read -r bin pkg; do
    [ -z "$pkg" ] && pkg=$bin
    if [ "${bin:-}" != "-" ] && ! check_command "${bin:-}"; then
      verbose "$bin not found, installing $pkg"
      install_packages "$pkg"
    elif [ "${bin:-}" = "-" ] && [ -n "${pkg:-}" ]; then
      verbose "Installing $pkg"
      install_packages "$pkg"
    fi
  done
}


make_owned_dir() {
  [ -z "$1" ] && error "make_owned_dir: no dir given"
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
      verbose "Creating group %s" "$NEW_GROUP"
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
