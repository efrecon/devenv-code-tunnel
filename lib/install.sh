#!/bin/sh

# Verify that file at $1 has sha512/sha256 checksum $2. When $3 is present, it
# is used to provide a description of the file. When $4 is present, it is the
# mode to use for the file (otherwise text mode is used, which should work in
# most cases). When no checksum is provided, a warning is issued.
checksum() {
  [ -z "$1" ] && error "checksum: no file given"
  if [ -n "${2:-}" ]; then
    if [ "$(printf %s "$2" | wc -c)" = "128" ]; then
      _sum=sha512
    elif [ "$(printf %s "$2" | wc -c)" = "64" ]; then
      _sum=sha256
    else
      error "checksum: invalid checksum length"
    fi
    if ! printf "%s %s%s\n" "$2" "${4:-" "}" "$1" | "${_sum}sum" -c - >/dev/null; then
      rm -f "$1"
      error "Checksum mismatch for ${3:-$1}"
    else
      trace "Checksum verified for ${3:-$1}"
    fi
  else
    warn "No checksum provided for ${3:-$1}. Skipping verification."
  fi
}


dir_owner() {
  [ -z "$1" ] && error "dir_owner: no directory given"
  if [ -d "$1" ]; then
    stat -c %u "$1"
  else
    dir_owner "$(dirname "$1")"
  fi
}


# $1 name of file at remote location
# $2 URL where to find checksums
# $3 local file to check (empty: same as $1)
# $4 nickname of the file for log output and info (empty: same as $3)
internet_checksum() {
  [ -z "$1" ] && error "internet_checksum: no remote file name given"
  [ -z "$2" ] && error "internet_checksum: no url given"
  debug "Verifying checksum for %s using %s" "$1" "$2"
  _tmp_sums=$(mktemp)
  download "$2" "$_tmp_sums"

  # Note we pick the first checksum we find and do not enforce it to be at the
  # beginning. This allows to support checksums that would be empbedded in HTML
  # (release) notes, e.g. cloudflared.
  _sum=$(grep -F "$1" "$_tmp_sums" | head -n 1 | grep -Eo '[0-9a-fA-F]{64}')
  [ -z "$_sum" ] && _sum=$(grep -F "$1" "$_tmp_sums" | head -n 1 | grep -Eo '[0-9a-fA-F]{128}')

  rm -f "$_tmp_sums"
  if [ -z "$_sum" ]; then
    error "Checksum not found for $1 in $2"
  fi

  checksum "${3:-$1}" "$_sum" "${4:-${3:-$1}}"
}


# Install a script from the internet. This is a convenience function that
# generates a log line to make this more appearent.
internet_script_installer() {
  [ -z "$1" ] && error "internet_script_installer: no url given"
  _tmp_script=$(mktemp -t "${2:-"$(basename "$1")"}.XXXXXX")
  download "$1" "$_tmp_script"
  if [ -n "${3:-}" ]; then
    checksum "$_tmp_script" "$3" "$2"
  fi
  verbose "Running downloaded script $_tmp_script"
  shift 3
  ${INSTALL_OPTIMIZE:-} bash -- "$_tmp_script" "$@"
  rm -f "$_tmp_script"
}


# $1 is the URL to download from.
# $2 is the target directory. Ownership will be respected.
# $3 is the name of the target file. Empty->basename of the URL.
# $4 is the checksum (or URL to) to verify. Empty->no verification.
internet_bin_installer() {
  [ -z "$1" ] && error "internet_bin_installer: no url given"
  [ -z "$2" ] && error "internet_bin_installer: no target directory given"

  # declare shortcuts for the arguments and download the file
  _tgt_bin=${3:-"$(basename "$1")"}
  _tmp_bin=$(mktemp -t "${_tgt_bin}.XXXXXX")
  download "$1" "$_tmp_bin"

  # Verify checksum if provided
  if [ -n "${4:-}" ]; then
    if printf %s\\n "$4" | grep -qE '^https?://'; then
      internet_checksum "$(basename "$1")" "$4" "$_tmp_bin" "$_tgt_bin"
    else
      checksum "$_tmp_bin" "$4" "$_tgt_bin"
    fi
  fi

  # Copy into destination directory, respecting ownership
  if [ "$(dir_owner "$2")" = "0" ]; then
    verbose "Installing %s to %s, as root" "$1" "${2%/}/$_tgt_bin"
    as_root mkdir -p "$2"
    as_root cp -f "$_tmp_bin" "${2%/}/$_tgt_bin"
    as_root chmod a+rx "${2%/}/$_tgt_bin"
  else
    verbose "Installing %s to %s" "$1" "${2%/}/$_tgt_bin"
    mkdir -p "$2"
    cp -f "$_tmp_bin" "${2%/}/$_tgt_bin"
    chmod a+rx "${2%/}/$_tgt_bin"
  fi

  # Clean up and return the path to the target binary
  rm -f "$_tmp_bin"
  printf "%s\n" "${2%/}/$_tgt_bin"
}


# $1 is the URL to download from.
# $2 is the target directory. Ownership will be respected.
# $3 is the name of the target file. Empty->basename of the URL.
# $4 is the checksum (or URL to) to verify. Empty->no verification.
# $5 is the pattern to search for inside the tgz. Empty->same as $3.
internet_bintgz_installer() {
  [ -z "$1" ] && error "internet_bintgz_installer: no url given"
  [ -z "$2" ] && error "internet_bintgz_installer: no target directory given"

  # declare shortcuts for the arguments and download the file
  _tgt_bin=${3:-"$(basename "$1")"}
  _tmp_tgz=$(mktemp -t "${_tgt_bin}.XXXXXX")
  download "$1" "$_tmp_tgz"

  # Verify checksum if provided
  if [ -n "${4:-}" ]; then
    if printf %s\\n "$4" | grep -qE '^https?://'; then
      internet_checksum "$(basename "$1")" "$4" "$_tmp_tgz" "$_tgt_bin"
    else
      checksum "$_tmp_tgz" "$4" "$_tgt_bin"
    fi
  fi

  # Extract to a temporary directory
  _tmp_d=$(mktemp -d -t "${_tgt_bin}.XXXXXX")
  tar -C "$_tmp_d" -zxf "$_tmp_tgz"

  # Find the target binary inside the tgz, respect ownership
  if [ "$(dir_owner "$2")" = "0" ]; then
    verbose "Installing from %s to %s, as root" "$1" "${2%/}/$_tgt_bin"
    as_root mkdir -p "$2"
    as_root find "$_tmp_d" -name "${5:-$_tgt_bin}" -type f -exec mv -f \{\} "${2%/}/$_tgt_bin" \;
    as_root chmod a+rx "${2%/}/$_tgt_bin"
  else
    verbose "Installing from %s to %s" "$1" "${2%/}/$_tgt_bin"
    mkdir -p "$2"
    find "$_tmp_d" -name "${5:-$_tgt_bin}" -type f -exec mv -f \{\} "${2%/}/$_tgt_bin" \;
    chmod a+rx "${2%/}/$_tgt_bin"
  fi

  # Clean up and return the path to the target binary
  rm -rf "$_tmp_d"
  rm -f "$_tmp_tgz"
  printf "%s\n" "${2%/}/$_tgt_bin"
}


# $1 is the URL to download from.
# $2 is the target directory. Ownership will be respected.
# $3 is the name of the target package. Empty->basename of the URL.
# $4 is the checksum (or URL to) to verify. Empty->no verification.
internet_tgz_installer() {
  [ -z "$1" ] && error "internet_tgz_installer: no url given"
  [ -z "$2" ] && error "internet_tgz_installer: no target directory given"

  # declare shortcuts for the arguments and download the file
  _tgt=${3:-"$(basename "$1")"}
  _tmp_tgz=$(mktemp -t "${_tgt}.XXXXXX")
  download "$1" "$_tmp_tgz"

  # Verify checksum if provided
  if [ -n "${4:-}" ]; then
    if printf %s\\n "$4" | grep -qE '^https?://'; then
      internet_checksum "$(basename "$1")" "$4" "$_tmp_tgz" "$_tgt"
    else
      checksum "$_tmp_tgz" "$4" "$_tgt"
    fi
  fi

  # Find the target binary inside the tgz, respect ownership
  _tgt_d=$2
  if [ "$(dir_owner "$_tgt_d")" = "0" ]; then
    verbose "Installing from %s to %s, as root" "$1" "$_tgt_d"
    as_root mkdir -p "$_tgt_d"
    shift 4
    as_root tar -C "$_tgt_d" -zxf "$_tmp_tgz" "$@"
  else
    verbose "Installing from %s to %s" "$1" "$_tgt_d"
    mkdir -p "$_tgt_d"
    shift 4
    tar -C "$_tgt_d" -zxf "$_tmp_tgz" "$@"
  fi

  # Clean up
  rm -f "$_tmp_tgz"
}
