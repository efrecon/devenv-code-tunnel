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

test_is_musl_os() {
  if [ -f /etc/alpine-release ]; then
    assert_true is_musl_os
  elif [ -f /etc/debian_version ]; then
    assert_false is_musl_os
  else
    skip "unknown distribution"
  fi
}

test_get_distro_version() {
  [ -f /etc/os-release ] || skip "no /etc/os-release"
  version=$(sed -n -E 's/^VERSION_ID="?([^"]*)"?$/\1/p' /etc/os-release)
  assert_eq "$version" "$(get_distro_version)"
}

test_install_ondemand_only_installs_missing() {
  # Replace the package installer, record what would be installed.
  # shellcheck disable=SC2329 # Called by install_ondemand
  install_packages() { echo "$*" >> "$TEST_TMPDIR/installed"; }
  install_ondemand <<'EOF2'
sh
missing-command-xyz some-package
other-missing-xyz
- always-package
EOF2
  assert_eq "some-package
other-missing-xyz
always-package" "$(cat "$TEST_TMPDIR/installed")"
}

# Users created by the tests below, unique per test.
_test_user() { printf 'dt%s\n' "$(generate_random 6 'a-z')"; }

_require_user_tools() {
  require_root
  require_cmd adduser chpasswd getent su
}

test_create_user_and_group() {
  _require_user_tools
  user=$(_test_user)
  create_user "$user:${user}grp"
  assert_contains "$(getent passwd "$user")" "$user:"
  assert_contains "$(getent group "${user}grp")" "${user}grp:"
  assert_true test -d "$(home_dir "$user")"
  assert_eq "$(home_dir "$user")/.local" "$(user_local_dir "$user")"
  shell=$(getent passwd "$user" | cut -d: -f7)
  assert_true test -x "$shell"
}

test_create_existing_user_fails() {
  _require_user_tools
  user=$(_test_user)
  create_user "$user"
  assert_fails create_user "$user"
}

test_create_user_with_prefix_of_existing_user() {
  _require_user_tools
  user=$(_test_user)
  create_user "${user}long"
  create_user "$user"
  assert_contains "$(getent passwd "$user")" "$user:"
}

test_xdg_user_dirs_owned_by_user() {
  _require_user_tools
  user=$(_test_user)
  create_user "$user"
  xdg_user_dirs "$user"
  home=$(home_dir "$user")
  for d in .config .cache .local/share .local/state .local/bin; do
    assert_true test -d "$home/$d"
    assert_eq "$user" "$(stat -c %U "$home/$d")" "owner of $d"
  done
}

test_make_owned_dir() {
  _require_user_tools
  user=$(_test_user)
  create_user "$user"
  make_owned_dir "$TEST_TMPDIR/a/b" "$user"
  assert_eq "$user" "$(stat -c %U "$TEST_TMPDIR/a/b")"
}

test_as_user_and_su_user() {
  _require_user_tools
  user=$(_test_user)
  create_user "$user"
  # The user must be able to read the temporary script of su_user.
  TMPDIR=/tmp
  assert_eq "$user" "$(su_user "$user" id -un)"
  assert_eq "$user" "$(as_user "$user" id -un)"
  assert_eq "root" "$(as_user root id -un)" "no switch when already that user"
}
