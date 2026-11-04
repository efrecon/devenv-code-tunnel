#!/bin/sh


wait_file() {
  [ -z "${1:-}" ] && error "wait_file: No file path given"
  while ! test -"${2:-f}" "$1"; do
    sleep 1
  done
  trace "Path at %s tested positive for -%s" "$1" "${2:-f}"
}

wait_infile() {
  [ -z "${1:-}" ] && error "wait_infile: No file path given"
  [ -z "${2:-}" ] && error "wait_infile: No expression provided"
  wait_file "$1"
  while ! grep -"${3:-E}" "$2" "$1"; do
    sleep 1
  done | head -n 1
}

_match_in_pairs() {
  _val=$1
  _opt=$2
  shift 2

  while [ "$#" != 0 ]; do
    if printf %s\\n "$_val" | grep -q -"$_opt" "$1"; then
      printf %s\\n "$2"
      return 0
    else
      shift 2
    fi
  done

  return 1;  # No match
}


# Print the current size of a file in bytes, 0 when it does not exist (yet).
# Record this before starting a process that writes to the file, and pass it to
# when_infile so that only lines written by that process are considered.
file_size() {
  [ -z "${1:-}" ] && error "file_size: No file path given"
  if [ -f "$1" ]; then
    wc -c < "$1" | tr -d '[:space:]'
  else
    printf '0\n'
  fi
}


# Watch the content of a file, starting at a byte offset, and whenever a line
# matches an expression, call a function with the content of the line. When the
# function returns true, end the loop and print the matching line. Otherwise,
# continue to watch the file. When the function is -, do not call it.
# $1: byte offset to start watching from, as returned by file_size. Content
#     before that offset is ignored. Lines written between taking the offset
#     and calling this function are not lost.
# $2: the file to watch
# $3: the grep matching format, e.g. F or E.
# $4 and further: a pattern, then a function, and so on.
when_infile() {
  [ -z "${1:-}" ] && error "when_infile: No byte offset given"
  [ -z "${2:-}" ] && error "when_infile: No file path given"
  [ -z "${3:-}" ] && error "when_infile: No grep matching format given"

  _offset=$1
  _fpath=$2
  _opt=$3
  shift 3
  wait_file "$_fpath"

  # We use a sub-shell so the main while loop can run independently and return
  # as soon as the condition is met but will keep running until it is met. See:
  # https://superuser.com/a/900134. tail -c +N is 1-based, hence the +1.
  ( tail -c "+$((_offset + 1))" -f -- "$_fpath" & ) | while IFS= read -r _line; do
    _fn=$(_match_in_pairs "$_line" "$_opt" "$@" || true)
    if [ -n "$_fn" ]; then
      trace "'%s' matches, sending for processing to %s" "$_line" "$_fn"
      if [ "$_fn" = "-" ] || "$_fn" "$_line"; then
        printf %s\\n "$_line"
        return 0
      fi
    fi
  done
}


wait_process_end() {
  [ -z "${1:-}" ] && error "wait_process_end: No PID given"
  while kill -0 "$1" 2>/dev/null; do
    sleep 1
  done
}
