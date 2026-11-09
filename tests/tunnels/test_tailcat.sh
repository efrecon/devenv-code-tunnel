#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the scripts and in wait_until
# Tests for share/tunnels/tailcat.sh, against fake tailcat and nc commands.

ADDR=tcABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdef

setup() {
  fake_path
  FAKE_CALLS=$TEST_TMPDIR/calls
  GIST=$TEST_TMPDIR/gist.txt
  OUT=$TEST_TMPDIR/out
  TUNNEL_NAME=mytunnel
  TUNNEL_USER_PREFIX=$TEST_TMPDIR/user
  TUNNEL_GIST_FILE=$GIST
  TUNNEL_REEXPOSE=-
  XDG_CONFIG_HOME=$TEST_TMPDIR/config
  KEY=$XDG_CONFIG_HOME/tailcat/keys/mytunnel.private.json
  export FAKE_CALLS TUNNEL_NAME TUNNEL_USER_PREFIX TUNNEL_GIST_FILE \
    TUNNEL_REEXPOSE XDG_CONFIG_HOME

  fake_cmd nc <<'EOF'
#!/bin/sh
exit 0
EOF
  # genkey --fixed-region --key <name>, or --key <name> serve <port>
  fake_cmd tailcat <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "\$FAKE_CALLS"
if [ "\$1" = "genkey" ]; then
  mkdir -p "\$XDG_CONFIG_HOME/tailcat/keys"
  echo '{}' > "\$XDG_CONFIG_HOME/tailcat/keys/\$4.private.json"
  exit 0
fi
echo "Serving on $ADDR"
sleep 1
EOF
}

_run() { run_script share/tunnels/tailcat.sh > "$OUT" 2>&1; }

test_generates_key_and_publishes() {
  _run
  assert_file "$KEY"
  assert_eq "genkey --fixed-region --key mytunnel
--key mytunnel serve 2222" "$(cat "$FAKE_CALLS")"
  gist=$(cat "$GIST")
  assert_contains "$gist" "tailcat ssh -p 2222 $(id -un)@$ADDR"
  assert_contains "$gist" "ProxyCommand='tailcat $ADDR 2222'"
  assert_match "$(tail -n 1 "$GIST")" '^Last updated: '
}

test_existing_key_is_reused() {
  mkdir -p "$(dirname "$KEY")"
  echo '{}' > "$KEY"
  _run
  assert_not_contains "$(cat "$FAKE_CALLS")" "genkey"
}

test_key_generation_failure() {
  fake_cmd tailcat <<'EOF'
#!/bin/sh
exit 0
EOF
  rc=0
  _run || rc=$?
  assert_ne 0 "$rc" "exit code"
  assert_contains "$(cat "$OUT")" "Failed to generate key"
}

test_missing_cli_exits_quietly() {
  rm -f "$FAKEBIN/tailcat"
  ! command -v tailcat >/dev/null 2>&1 || skip "tailcat installed on this system"
  _run
  assert_no_file "$GIST"
}
