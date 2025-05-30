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


# Watch the content of a file and whenever a line matches an expression, call a
# function with the content of the line. When the function returns true, end the
# loop and print the matching line. Otherwise, continue to watch the file. When
# the function is -, do not call it.
# $1: the file to watch
# $2: the grep matching format, e.g. F or E.
# $3 and further: a pattern, then a function, and so on.
when_infile() {
  [ -z "${1:-}" ] && error "when_infile: No file path given"
  [ -z "${2:-}" ] && error "when_infile: No grep matching format given"
  wait_file "$1"

  _fpath=$1
  _opt=$2
  shift 2
  # We use a sub-shell so the main while loop can run independently and return
  # as soon as the condition is met but will keep running until it is met. See:
  # https://superuser.com/a/900134
  ( tail -f -- "$_fpath" & ) | while IFS= read -r _line; do
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
  while kill -0 "$1"; do
    sleep 1
  done
}
