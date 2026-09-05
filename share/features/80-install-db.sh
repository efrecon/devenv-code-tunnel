#!/bin/sh

# Shell sanity. Stop on errors, undefined variables and pipeline errors.
set -eu
# shellcheck disable=SC3040 # now part of POSIX, but not everywhere yet!
if set -o | grep -q 'pipefail'; then set -o pipefail; fi

# Absolute location of the script where this script is located.
INSTALL_ROOTDIR=$( cd -P -- "$(dirname -- "$(command -v -- "$(realpath "$0")")")" && pwd -P )

# Hurry up and find the libraries
for lib in log common install system; do
  for d in ../../lib ../lib lib; do
    if [ -d "${INSTALL_ROOTDIR}/$d" ]; then
      # shellcheck disable=SC1090
      . "${INSTALL_ROOTDIR}/$d/${lib}.sh"
      break
    fi
  done
done


# All following vars have defaults here, but will be set and inherited from
# calling install.sh script in the normal case.
: "${INSTALL_VERBOSE:=0}"
: "${INSTALL_LOG:=2}"


log_init INSTALL


if is_os_family alpine; then
  as_root mkdir -p /usr/share/man
  install_packages mysql-client postgresql18-client sqlite redis
elif is_os_family debian; then
  install_packages default-mysql-client postgresql-common sqlite3 redis-server redis-tools
  # Automatically configure the official PGDG Apt repository
  as_root /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
  install_packages postgresql-client-18
else
  error "Unsupported OS family: %s" "$(get_distro_name)"
fi
