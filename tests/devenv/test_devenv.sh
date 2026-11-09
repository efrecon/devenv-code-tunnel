#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the scripts and in wait_until
# Tests for devenv.sh, against fake container orchestrators. The fakes record
# each call in $FAKE_CALLS, one argument per bracket. The arguments to "run" are
# also recorded one per line in $FAKE_RUN, and the TUNNEL_ variables that the
# run would see in $FAKE_ENV.

IMAGE=ghcr.io/efrecon/devenv-code-tunnel-alpine:main

# Commands that change what devenv.sh does when found: never resolve them on
# the host, only as fakes. msb, podman and docker are orchestrators, krun is a
# runtime picked by default, gh provides a GitHub token.
HOST_HIDDEN="docker podman msb krun gh"

# Restrict PATH to the fakes, and to SYSBIN: links to all the commands of the
# system directories, except the ones in HOST_HIDDEN. Commands from the host
# that devenv.sh would pick automatically are then not reachable at all, even
# when their fake is removed.
_isolated_path() {
  fake_path
  SYSBIN=$TEST_TMPDIR/sysbin
  mkdir -p "$SYSBIN"
  for _d in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
    [ -d "$_d" ] || continue
    # One ln per directory, for speed. Existing links are not replaced, so the
    # first directory wins, as in a PATH lookup: ignore the errors about them.
    ln -s "$_d"/* "$SYSBIN/" 2>/dev/null || true
  done
  for _n in $HOST_HIDDEN; do
    rm -f "$SYSBIN/$_n"
  done
  PATH=$FAKEBIN:$SYSBIN
  export PATH
}

setup() {
  _isolated_path
  FAKE_CALLS=$TEST_TMPDIR/calls
  FAKE_RUN=$TEST_TMPDIR/run
  FAKE_ENV=$TEST_TMPDIR/env
  OUT=$TEST_TMPDIR/out
  HOME=$TEST_TMPDIR/home
  CONF1=$TEST_TMPDIR/conf1
  CONF2=$TEST_TMPDIR/conf2
  WORK=$TEST_TMPDIR/work
  mkdir -p "$HOME" "$CONF1" "$CONF2" "$WORK"
  DEVENV_PATH=$CONF1:$CONF2
  export FAKE_CALLS FAKE_RUN FAKE_ENV HOME DEVENV_PATH
  # Not part of what users pass, set by the test framework.
  unset TUNNEL_PREFIX

  for orchestrator in docker podman msb; do
    fake_cmd "$orchestrator" <<'EOF'
#!/bin/sh
{ printf '%s' "$(basename "$0")"; printf ' [%s]' "$@"; printf '\n'; } >> "$FAKE_CALLS"
case "$1" in
  ps) [ -n "${FAKE_EXISTING:-}" ] && echo "$FAKE_EXISTING"; exit 0;;
  volume) [ "$2" = ls ] && echo "${FAKE_VOLUMES:-}"; exit 0;;
  image) exit 0;;
  container|sandbox)
    if [ "$2" = run ]; then
      shift 2
      printf '%s\n' "$@" > "$FAKE_RUN"
      { env | grep '^TUNNEL_' | sort; } > "$FAKE_ENV" || true
    fi
    exit 0;;
esac
EOF
  done
  fake_cmd hostname <<'EOF'
#!/bin/sh
echo myhost.example.com
EOF
}

# Only keep the fake orchestrators passed as arguments. Skip the test if any of
# the commands in HOST_HIDDEN still resolves to something else than a fake.
_only() {
  for o in docker podman msb; do
    case " $* " in
      *" $o "*) ;;
      *) rm -f "$FAKEBIN/$o";;
    esac
  done
  for o in $HOST_HIDDEN; do
    _found=$(command -v "$o" 2>/dev/null || true)
    case "$_found" in
      "" | "$FAKEBIN/$o") ;;
      *) skip "$o from the host is visible at $_found";;
    esac
  done
}

_devenv() { run_script devenv.sh "$@" > "$OUT" 2>&1 < /dev/null; }

# Arguments of the run, separated by |, with a leading and trailing |.
_run_args() { printf '|%s|\n' "$(tr '\n' '|' < "$FAKE_RUN" | sed 's/|$//')"; }

test_docker_directory_defaults() {
  _only docker
  _devenv -i - -T - "$WORK" -- -v
  assert_eq "|--privileged|-t|--rm|--name|work|--hostname|myhost-work|-v|$WORK:/home/coder:Z|$IMAGE|-v|" "$(_run_args)"
  assert_contains "$(cat "$FAKE_CALLS")" "docker [image] [pull] [$IMAGE]"
  assert_not_contains "$(cat "$FAKE_CALLS")" "[volume] [create]"
}

test_orchestrator_preference() {
  _only docker podman
  _devenv -i - -T - "$WORK"
  assert_match "$(head -n 1 "$FAKE_CALLS")" '^podman '
}

test_no_orchestrator() {
  # Orchestrators from the host are not reachable, see _isolated_path and _only.
  _only
  rc=0
  _devenv -i - -T - "$WORK" || rc=$?
  assert_ne 0 "$rc"
  assert_contains "$(cat "$OUT")" "No orchestrator found"
}

test_requested_orchestrator_missing() {
  _only docker
  rc=0
  _devenv -o podman -i - -T - "$WORK" || rc=$?
  assert_ne 0 "$rc"
  assert_contains "$(cat "$OUT")" "Orchestrator not found: podman"
}

test_options() {
  _only docker
  _devenv -i - -T - -I example/image:1 -N box -t tun "$WORK"
  assert_contains "$(_run_args)" "|--name|box|--hostname|tun|"
  assert_contains "$(_run_args)" "|example/image:1|"
}

test_detach() {
  _only docker
  _devenv -d -i - -T - "$WORK"
  assert_match "$(_run_args)" '^\|--privileged\|--restart\|unless-stopped\|-d\|--name\|'
}

test_passthrough_options() {
  _only docker
  _devenv -i - -T - --memory 2g --cpus=2 "$WORK"
  assert_contains "$(head -n 3 "$FAKE_RUN" | tr '\n' ' ')" "--memory 2g --cpus=2"
}

test_relative_directory_is_mounted_with_full_path() {
  _only docker
  mkdir -p "$WORK/sub"
  for dir in work ./work work/sub/.. "work/"; do
    rm -f "$FAKE_RUN"
    _devenv -i - -T - "$dir"
    assert_contains "$(_run_args)" "|-v|$WORK:/home/coder:Z|" "mount for $dir"
    assert_contains "$(_run_args)" "|--name|work|" "name for $dir"
  done
  assert_not_contains "$(cat "$FAKE_CALLS")" "[volume] [create]"
}

test_current_directory_by_dot() {
  _only docker
  ( cd "$WORK" && _devenv -i - -T - . )
  assert_contains "$(_run_args)" "|-v|$WORK:/home/coder:Z|"
}

test_directory_through_symlink_is_resolved() {
  _only docker
  ln -s "$WORK" "$TEST_TMPDIR/link"
  _devenv -i - -T - link
  assert_contains "$(_run_args)" "|-v|$WORK:/home/coder:Z|"
}

test_volume_is_created() {
  _only docker
  _devenv -i - -T - myvolume
  assert_contains "$(cat "$FAKE_CALLS")" "docker [volume] [create] [myvolume]"
  assert_contains "$(_run_args)" "|-v|myvolume:/home/coder:Z|"
  assert_contains "$(_run_args)" "|--name|myvolume|"
}

test_existing_volume_not_created() {
  _only docker
  FAKE_VOLUMES=myvolume _devenv -i - -T - myvolume
  assert_not_contains "$(cat "$FAKE_CALLS")" "[volume] [create]"
}

test_existing_container_is_removed() {
  _only docker
  FAKE_EXISTING=0123456789ab _devenv -i - -T - "$WORK"
  assert_contains "$(cat "$FAKE_CALLS")" "docker [container] [rm] [-f] [work]"
}

test_local_image_not_pulled() {
  _only docker
  _devenv -i - -T - -I localhost/devenv:dev "$WORK"
  assert_not_contains "$(cat "$FAKE_CALLS")" "[pull]"
}

test_dry_run() {
  _only docker
  _devenv -n -i - -T ghp_secret "$WORK"
  assert_no_file "$FAKE_RUN"
  assert_contains "$(cat "$OUT")" "Dry-run mode, would run: docker container run"
  assert_no_file "$HOME/.local/state/devenv/work/github-token" "token not stored"
}

test_long_tunnel_name_is_truncated() {
  _only docker
  _devenv -i - -T - -N a-very-long-container-name "$WORK"
  tunnel=$(sed -n '/^--hostname$/{n;p;}' "$FAKE_RUN")
  assert_eq 20 "${#tunnel}" "tunnel name size"
  assert_match "$tunnel" '^myhost-a-very-\-[0-9a-f]{5}$'
}

test_identity_guessed_from_ssh_directory() {
  _only docker
  mkdir -p "$HOME/.ssh"
  for k in id_rsa id_ed25519; do
    touch "$HOME/.ssh/$k" "$HOME/.ssh/$k.pub"
  done
  _devenv -T - "$WORK"
  assert_contains "$(_run_args)" "|-v|$HOME/.ssh/id_ed25519:/home/coder/.ssh/id_ed25519:Z,ro|"
  assert_contains "$(_run_args)" "|-v|$HOME/.ssh/id_ed25519.pub:/home/coder/.ssh/id_ed25519.pub:Z,ro|"
  assert_not_contains "$(_run_args)" "id_rsa"
}

test_identity_requires_public_key() {
  _only docker
  touch "$TEST_TMPDIR/mykey"
  rc=0
  _devenv -i "$TEST_TMPDIR/mykey" -T - "$WORK" || rc=$?
  assert_ne 0 "$rc"
  assert_contains "$(cat "$OUT")" "Public SSH key file not found"
}

test_token_value_is_stored_and_mounted() {
  _only docker
  _devenv -i - -T ghp_secret "$WORK"
  token_file=$HOME/.local/state/devenv/work/github-token
  assert_eq "ghp_secret" "$(cat "$token_file")"
  assert_eq 600 "$(stat -c %a "$token_file")"
  assert_contains "$(_run_args)" "|-v|$token_file:/run/secrets/github-token:Z,ro|"
  assert_not_contains "$(_run_args)" "ghp_secret" "token never on the command line"
}

test_token_file_is_mounted() {
  _only docker
  printf 'ghp_fromfile\n' > "$TEST_TMPDIR/token"
  _devenv -i - -T "$TEST_TMPDIR/token" "$WORK"
  assert_contains "$(_run_args)" "|-v|$TEST_TMPDIR/token:/run/secrets/github-token:Z,ro|"
}

test_token_file_must_exist() {
  _only docker
  rc=0
  _devenv -i - -T /no/such/token "$WORK" || rc=$?
  assert_ne 0 "$rc"
  assert_contains "$(cat "$OUT")" "GitHub token file not found"
}

test_token_from_gh() {
  _only docker
  fake_cmd gh <<'EOF'
#!/bin/sh
[ "$*" = "auth token --hostname github.com" ] && echo ghp_fromgh
EOF
  _devenv -i - "$WORK"
  assert_eq "ghp_fromgh" "$(cat "$HOME/.local/state/devenv/work/github-token")"
}

test_no_token_removes_environment_token() {
  _only docker
  TUNNEL_GITHUB_TOKEN=ghp_env TUNNEL_OTHER=kept _devenv -i - -T - "$WORK"
  assert_not_contains "$(cat "$FAKE_ENV")" "TUNNEL_GITHUB_TOKEN"
  assert_not_contains "$(_run_args)" "/run/secrets/github-token"
  assert_contains "$(_run_args)" "|-e|TUNNEL_OTHER|"
}

test_podman_with_krun() {
  _only podman
  _devenv -i - -T - -r krun "$WORK"
  args=$(_run_args)
  assert_contains "$args" "|--runtime=krun|--user|0:0|-e|TUNNEL_CLOUDFLARE_PROTOCOL=http2|"
  assert_contains "$args" "|--userns=keep-id:uid=1000,gid=1000|"
  assert_not_contains "$args" "--privileged"
}

test_podman_privileged_without_krun() {
  # krun is never visible from the host, see HOST_HIDDEN: _only skips otherwise.
  _only podman
  assert_false command -v krun
  _devenv -i - -T - "$WORK"
  assert_match "$(_run_args)" '^\|--privileged\|--userns=keep-id:uid=1000,gid=1000\|'
  assert_not_contains "$(_run_args)" "--runtime"
}

test_podman_prefers_krun_when_available() {
  _only podman
  fake_cmd krun <<'EOF'
#!/bin/sh
exit 0
EOF
  _devenv -i - -T - "$WORK"
  args=$(_run_args)
  assert_contains "$args" "|--runtime=krun|--user|0:0|-e|TUNNEL_CLOUDFLARE_PROTOCOL=http2|"
  assert_not_contains "$args" "--privileged"
}

test_msb_sandbox() {
  _only msb
  _devenv -i - -T - "$WORK" -- -v
  assert_contains "$(cat "$FAKE_CALLS")" "msb [sandbox] [run]"
  assert_eq "|-t|--name|work|--hostname|myhost-work|-v|$WORK:/home/coder:uid=1000,gid=1000|$IMAGE|--|-v|" "$(_run_args)"
}

test_env_files() {
  _only docker
  cr=$(printf '\r')
  cat > "$CONF1/devenv.env" <<EOF
# A comment

DEVENV_IMAGE=example/fromfile:1
export TUNNEL_QUOTED="quoted value"   # comment
TUNNEL_SINGLE='single \$(touch $TEST_TMPDIR/injected)'
TUNNEL_PLAIN=plain value # trailing comment
TUNNEL_DOS=dos${cr}
TUNNEL_FROM_ENV=file
DEVENV_NAME=fromfile1
NOT_OURS=1
DEVENV_PATH=/nowhere
BAD-NAME=1
not a key value line
EOF
  printf 'DEVENV_NAME=fromfile2\n' > "$CONF2/.devenv.env"
  TUNNEL_FROM_ENV="env" _devenv -i - -T - "$WORK"
  env=$(cat "$FAKE_ENV")
  assert_contains "$env" "TUNNEL_QUOTED=quoted value"
  assert_contains "$env" "TUNNEL_SINGLE=single \$(touch $TEST_TMPDIR/injected)"
  assert_no_file "$TEST_TMPDIR/injected" "values are never evaluated"
  assert_contains "$env" "TUNNEL_PLAIN=plain value
"
  assert_contains "$env" "TUNNEL_DOS=dos
"
  assert_contains "$env" "TUNNEL_FROM_ENV=env" "environment takes precedence"
  assert_contains "$(_run_args)" "|-e|TUNNEL_QUOTED|"
  assert_contains "$(_run_args)" "|example/fromfile:1|"
  assert_contains "$(_run_args)" "|--name|fromfile2|" "later files override"
  out=$(cat "$OUT")
  assert_contains "$out" "NOT_OURS is neither DEVENV_ nor TUNNEL_"
  assert_contains "$out" "DEVENV_PATH can only be set from the environment"
  assert_contains "$out" "Invalid variable name BAD-NAME"
  assert_contains "$out" "Not a KEY=VALUE line"
}

test_options_override_env_files() {
  _only docker
  printf 'DEVENV_IMAGE=example/fromfile:1\n' > "$CONF1/devenv.env"
  _devenv -i - -T - -I example/option:2 "$WORK"
  assert_contains "$(_run_args)" "|example/option:2|"
}

test_help() {
  _only docker
  _devenv -h
  assert_contains "$(cat "$OUT")" "Usage: devenv.sh"
  assert_no_file "$FAKE_RUN"
}
