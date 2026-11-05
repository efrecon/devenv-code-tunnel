#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for lib/system.sh

setup() {
  load_lib log common system
}

# Put a fake uname printing $1 for -m and $2 otherwise first in the PATH.
_fake_uname() {
  mkdir -p "$TEST_TMPDIR/fakebin"
  make_script "$TEST_TMPDIR/fakebin/uname" <<EOF
#!/bin/sh
if [ "\${1:-}" = "-m" ]; then echo "$1"; else echo "${2:-Linux}"; fi
EOF
  PATH=$TEST_TMPDIR/fakebin:$PATH
}

test_command_present() {
  assert_true command_present sh
  assert_false command_present this-command-does-not-exist
}

test_check_command_warns_when_missing() {
  CODER_LOG=1
  out=$(check_command this-command-does-not-exist || true)
  assert_contains "$out" "Command not found"
}

test_mktemp_ext_adds_extension() {
  f=$(mktemp_ext myprefix pid)
  assert_match "$f" "^${TEST_TMPDIR}/myprefix\.[A-Za-z0-9]{6}\.pid$"
  assert_file "$f"
  f=$(mktemp_ext other .json)
  assert_match "$f" '/other\.[A-Za-z0-9]{6}\.json$' "leading dot is optional"
}

test_mktemp_ext_without_extension() {
  f=$(mktemp_ext plain)
  assert_match "$f" '/plain\.[A-Za-z0-9]{6}$'
  assert_file "$f"
}

test_mktemp_ext_restrictive_permissions() {
  f=$(mktemp_ext perms txt)
  assert_eq "600" "$(stat -c %a "$f")"
}

test_mktemp_ext_in_directory() {
  mkdir "$TEST_TMPDIR/sub"
  f=$(mktemp_ext indir log "$TEST_TMPDIR/sub/")
  assert_match "$f" "^${TEST_TMPDIR}/sub/indir\.[A-Za-z0-9]{6}\.log$"
}

test_mktemp_ext_unique_and_no_leftovers() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    mktemp_ext many pid
  done > "$TEST_TMPDIR/names"
  assert_eq 10 "$(sort -u "$TEST_TMPDIR/names" | wc -l | tr -d ' ')"
  # Only the files with the extension remain, not the base files from mktemp.
  assert_eq 0 "$(find "$TEST_TMPDIR" -name 'many.??????' | wc -l | tr -d ' ')"
}

test_get_arch_known_mappings() {
  _fake_uname x86_64
  assert_eq x64 "$(get_arch)"
  _fake_uname aarch64
  assert_eq arm64 "$(get_arch)"
  _fake_uname armv7l
  assert_eq armhf "$(get_arch)"
}

test_get_arch_overrides_and_unknown() {
  _fake_uname x86_64
  assert_eq amd64 "$(get_arch x86_64 amd64)"
  _fake_uname riscv64
  assert_eq riscv64 "$(get_arch)"
}

test_get_golang_arch() {
  _fake_uname x86_64
  assert_eq amd64 "$(get_golang_arch)"
  _fake_uname aarch64
  assert_eq arm64 "$(get_golang_arch)"
  _fake_uname armv6l
  assert_eq arm "$(get_golang_arch)"
}

test_get_os() {
  _fake_uname x86_64 Linux
  assert_eq linux "$(get_os)"
}

test_distro_information() {
  [ -f /etc/os-release ] || skip "no /etc/os-release"
  id=$(sed -n -E 's/^ID="?([^"]*)"?$/\1/p' /etc/os-release)
  assert_eq "$id" "$(get_distro_name)"
  assert_true is_os_family "$id"
  assert_false is_os_family "no-such-distribution"
}

test_index() {
  assert_eq a "$(_index 0 a b c)"
  assert_eq c "$(_index 2 a b c)"
}

_children() { ps_children "$1" 2>/dev/null | wc -l | tr -d ' '; }

test_ps_children_and_kill_tree() {
  [ -d /proc/self ] || skip "no /proc"
  make_script "$TEST_TMPDIR/tree.sh" <<'EOF'
#!/bin/sh
sleep 30 &
sleep 30 &
wait
EOF
  "$TEST_TMPDIR/tree.sh" &
  pid=$!
  wait_until 5 '[ "$(_children "$pid")" -eq 2 ]'
  killed=$(kill_tree "$pid")
  assert_eq 3 "$(printf '%s\n' "$killed" | wc -l | tr -d ' ')"
  assert_eq "$pid" "$(printf '%s\n' "$killed" | tail -n 1)" "parent is killed last"
  wait "$pid" 2>/dev/null || true
  for p in $killed; do
    wait_until 5 'is_stopped "$p"'
  done
}

test_as_root_runs_directly_as_root() {
  [ "$(id -u)" = "0" ] || skip "not running as root"
  assert_eq 0 "$(as_root id -u)"
}
