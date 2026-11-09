#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for share/orchestration/gist.sh: commit and push changes to files in a
# git clone. A local bare repository stands in for the gist at GitHub.

setup() {
  require_cmd git
  # Isolate from the git configuration of the user (signing, hooks, etc.).
  HOME=$TEST_TMPDIR/home
  mkdir -p "$HOME"
  GIT_CONFIG_NOSYSTEM=1
  GIT_AUTHOR_NAME=Tester
  GIT_AUTHOR_EMAIL=tester@example.com
  GIT_COMMITTER_NAME=Tester
  GIT_COMMITTER_EMAIL=tester@example.com
  export HOME GIT_CONFIG_NOSYSTEM GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

  ORIGIN=$TEST_TMPDIR/origin.git
  CLONE=$TEST_TMPDIR/clone
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$CLONE" 2>/dev/null
  printf 'init\n' > "$CLONE/README"
  git -C "$CLONE" add README
  git -C "$CLONE" commit -q -m "init"
  git -C "$CLONE" push -q -u origin HEAD 2>/dev/null
}

_origin_commits() { git --git-dir="$ORIGIN" rev-list --count HEAD; }

test_pushes_changes() {
  printf 'tunnel details\n' > "$CLONE/tunnel.txt"
  run_orchestration gist -- "$CLONE/tunnel.txt"
  assert_eq 2 "$(_origin_commits)"
  assert_eq "tunnel details" "$(git --git-dir="$ORIGIN" show HEAD:tunnel.txt)"
}

test_no_commit_without_changes() {
  printf 'tunnel details\n' > "$CLONE/tunnel.txt"
  run_orchestration gist -- "$CLONE/tunnel.txt"
  run_orchestration gist -- "$CLONE/tunnel.txt"
  assert_eq 2 "$(_origin_commits)"
}

test_ignores_missing_files() {
  run_orchestration gist -- "$CLONE/missing.txt"
  assert_eq 1 "$(_origin_commits)"
}
