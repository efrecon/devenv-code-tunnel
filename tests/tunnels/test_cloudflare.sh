#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the scripts and in wait_until
# Tests for share/tunnels/cloudflare.sh, against fake cloudflared and nc
# commands. The fake cloudflared records its arguments and the TUNNEL_
# variables it sees, then prints a quick tunnel URL.

setup() {
  fake_path
  FAKE_CALLS=$TEST_TMPDIR/calls
  FAKE_ENV=$TEST_TMPDIR/env
  GIST=$TEST_TMPDIR/gist.txt
  OUT=$TEST_TMPDIR/out
  TUNNEL_NAME=mytunnel
  TUNNEL_USER_PREFIX=$TEST_TMPDIR/user
  TUNNEL_GIST_FILE=$GIST
  TUNNEL_REEXPOSE=-
  export FAKE_CALLS FAKE_ENV TUNNEL_NAME TUNNEL_USER_PREFIX TUNNEL_GIST_FILE \
    TUNNEL_REEXPOSE

  # sshd is considered up.
  fake_cmd nc <<'EOF'
#!/bin/sh
exit 0
EOF
  fake_cmd cloudflared <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_CALLS"
env | grep '^TUNNEL_' >> "$FAKE_ENV" || true
echo "INF +--------------------------------------------------------+"
echo "INF |  https://random-words-here.trycloudflare.com           |"
sleep 1
EOF
  mkdir -p "$TUNNEL_PREFIX/etc"
  printf 'ssh-ed25519 AAAAHOSTKEY root@host\n' > "$TUNNEL_PREFIX/etc/ssh_host_ed25519_key.pub"
}

_run() { run_script share/tunnels/cloudflare.sh "$@" > "$OUT" 2>&1; }

test_publishes_ssh_commands() {
  _run
  gist=$(cat "$GIST")
  assert_contains "$gist" "ssh-keygen -R mytunnel && echo 'mytunnel ssh-ed25519 AAAAHOSTKEY' >> ~/.ssh/known_hosts"
  assert_contains "$gist" "ProxyCommand='cloudflared access tcp --hostname https://random-words-here.trycloudflare.com'"
  assert_contains "$gist" "$(id -un)@mytunnel"
  assert_contains "$gist" "Host mytunnel"
  assert_match "$(tail -n 1 "$GIST")" '^Last updated: '
}

test_cloudflared_arguments() {
  _run --extra
  assert_eq "tunnel --no-autoupdate --protocol auto --url tcp://localhost:2222 --extra" "$(cat "$FAKE_CALLS")"
}

test_protocol_and_port() {
  TUNNEL_CLOUDFLARE_PROTOCOL=http2 TUNNEL_SSH=2022 _run
  assert_eq "tunnel --no-autoupdate --protocol http2 --url tcp://localhost:2022" "$(cat "$FAKE_CALLS")"
}

test_tunnel_variables_hidden_from_cloudflared() {
  _run
  assert_eq "" "$(cat "$FAKE_ENV")"
}

test_log_under_tunnel_prefix() {
  _run
  log=$TUNNEL_PREFIX/log/cloudflared.log
  assert_file "$log"
  assert_contains "$(cat "$log")" "random-words-here.trycloudflare.com"
  assert_no_file "$TUNNEL_PREFIX/log/clear.log" "named after cloudflared"
}

test_log_reexposed_in_output() {
  TUNNEL_REEXPOSE=cloudflared _run
  assert_match "$(cat "$OUT")" '>+cloudflared<+ .*INF \|  https://random-words-here\.trycloudflare\.com'
}

test_waits_for_sshd() {
  fake_cmd nc <<EOF
#!/bin/sh
# Fail the first time only.
[ -f "$TEST_TMPDIR/nc.once" ] && exit 0
touch "$TEST_TMPDIR/nc.once"
exit 1
EOF
  _run
  assert_file "$TEST_TMPDIR/nc.once"
  assert_contains "$(cat "$GIST")" "trycloudflare.com"
}

test_missing_cli_exits_quietly() {
  rm -f "$FAKEBIN/cloudflared"
  ! command -v cloudflared >/dev/null 2>&1 || skip "cloudflared installed on this system"
  _run
  assert_no_file "$GIST"
}
