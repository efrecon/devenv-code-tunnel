#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for lib/install.sh. Downloads are replaced by copies of local files, the
# installers themselves are exercised when building the Docker images.

setup() {
  load_lib log common system install
  # Replace download from common.sh, loaded above.
  # shellcheck disable=SC2329 # Called by the installers
  download() { _test_download "$@"; }
  SRC=$TEST_TMPDIR/src
  DST=$TEST_TMPDIR/dst
  mkdir -p "$SRC"
}

# Replacement for download: copy the file in $SRC named after the basename of
# the URL (without query) to $2, or to stdout.
_test_download() {
  _src=$SRC/$(basename "${1%%[?#]*}")
  [ -f "$_src" ] || fail "test download: no file $_src for $1"
  if [ -n "${2:-}" ]; then cp "$_src" "$2"; else cat "$_src"; fi
}

_sha256() { sha256sum "$1" | cut -d' ' -f1; }

# Make a tgz at $1 containing the files passed as further arguments, relative to
# the directory $SRC/tree.
_make_tgz() {
  _out=$1
  shift
  tar -C "$SRC/tree" -czf "$_out" "$@"
}

# No temporary file should be left behind by the installers.
_assert_no_leftovers() {
  _left=$(find "$TEST_TMPDIR" -maxdepth 1 -type f | grep -v '/count$' || true)
  assert_eq "" "$_left" "temporary files left"
}

test_url_encode() {
  assert_eq "a%20b%2Fc" "$(url_encode "a b/c")"
  assert_eq "safe-._~09AZaz" "$(url_encode "safe-._~09AZaz")"
  assert_eq "a b%2Fc" "$(url_encode "a b/c" "A-Za-z ")"
}

test_url_extension() {
  assert_eq sh "$(url_extension https://example.com/y/install.sh)"
  assert_eq ps1 "$(url_extension "https://example.com/script.ps1?ref=main#top")"
  assert_eq gz "$(url_extension https://example.com/tool_1.9_linux_amd64.gz)"
  assert_eq tgz "$(url_extension https://example.com/a.tgz)"
  assert_eq "" "$(url_extension https://gist.githubusercontent.com/u/id/raw)"
  assert_eq "" "$(url_extension https://example.com/tea-0.9.2-linux-amd64)"
}

test_tgz_stem() {
  assert_eq gh_2.1_linux "$(tgz_stem gh_2.1_linux.tar.gz)"
  assert_eq a "$(tgz_stem a.tgz)"
  assert_eq gh "$(tgz_stem gh)"
}

test_checksum_sha256_and_sha512() {
  printf 'content\n' > "$SRC/file"
  checksum "$SRC/file" "$(_sha256 "$SRC/file")"
  checksum "$SRC/file" "$(sha512sum "$SRC/file" | cut -d' ' -f1)"
  assert_file "$SRC/file"
}

test_checksum_mismatch_removes_file() {
  printf 'content\n' > "$SRC/file"
  assert_fails checksum "$SRC/file" "$(printf '%064d' 0)"
  assert_no_file "$SRC/file"
}

test_checksum_invalid_length() {
  printf 'content\n' > "$SRC/file"
  assert_fails checksum "$SRC/file" "abc123"
}

test_checksum_empty_only_warns() {
  CODER_LOG=1
  printf 'content\n' > "$SRC/file"
  assert_contains "$(checksum "$SRC/file" "")" "No checksum provided"
}

test_dir_ownership() {
  me="$(id -u):$(id -g)"
  assert_eq "$me" "$(dir_ownership "$TEST_TMPDIR")"
  assert_eq "$me" "$(dir_ownership "$TEST_TMPDIR/not/yet/created")" "closest parent"
}

test_internet_checksum_from_sums_file() {
  printf 'binary\n' > "$SRC/tool-linux"
  printf '%s  tool-linux\n%064d  other\n' "$(_sha256 "$SRC/tool-linux")" 0 > "$SRC/sums.txt"
  internet_checksum tool-linux https://example.com/sums.txt "$SRC/tool-linux"
  _assert_no_leftovers
}

test_internet_checksum_embedded_in_html() {
  printf 'binary\n' > "$SRC/tool-linux"
  printf '<p>tool-linux: <code>%s</code></p>\r\n' "$(_sha256 "$SRC/tool-linux")" > "$SRC/notes.html"
  internet_checksum tool-linux https://example.com/notes.html "$SRC/tool-linux"
}

test_internet_checksum_missing() {
  printf 'binary\n' > "$SRC/tool-linux"
  printf 'nothing here\n' > "$SRC/sums.txt"
  assert_fails internet_checksum tool-linux https://example.com/sums.txt "$SRC/tool-linux"
}

test_internet_bin_installer() {
  printf '#!/bin/sh\necho tool\n' > "$SRC/tool-1.2.3-linux"
  out=$(internet_bin_installer https://example.com/tool-1.2.3-linux "$DST" tool "$(_sha256 "$SRC/tool-1.2.3-linux")")
  assert_eq "$DST/tool" "$out"
  assert_eq "tool" "$("$DST/tool")"
  _assert_no_leftovers
}

test_internet_bin_installer_gunzips() {
  printf '#!/bin/sh\necho unzipped\n' | gzip -c > "$SRC/tool_linux.gz"
  internet_bin_installer https://example.com/tool_linux.gz "$DST" tool >/dev/null
  assert_eq "unzipped" "$("$DST/tool")"
  _assert_no_leftovers
}

test_internet_bin_installer_bad_checksum() {
  printf 'binary\n' > "$SRC/tool"
  assert_fails internet_bin_installer https://example.com/tool "$DST" tool "$(printf '%064d' 0)"
  assert_no_file "$DST/tool"
}

test_internet_bintgz_installer() {
  mkdir -p "$SRC/tree/tool-1.0/bin"
  printf '#!/bin/sh\necho from tgz\n' > "$SRC/tree/tool-1.0/bin/tool"
  printf 'readme\n' > "$SRC/tree/tool-1.0/README"
  _make_tgz "$SRC/tool-1.0.tar.gz" tool-1.0
  out=$(internet_bintgz_installer https://example.com/tool-1.0.tar.gz "$DST" tool)
  assert_eq "$DST/tool" "$out"
  assert_eq "from tgz" "$(sh "$DST/tool")"
  assert_true test -x "$DST/tool"
  assert_no_file "$DST/README"
  _assert_no_leftovers
}

test_internet_bintgz_installer_with_pattern() {
  mkdir -p "$SRC/tree"
  printf '#!/bin/sh\necho renamed\n' > "$SRC/tree/tool_linux_amd64"
  _make_tgz "$SRC/tool.tgz" tool_linux_amd64
  internet_bintgz_installer https://example.com/tool.tgz "$DST" tool "" 'tool_linux_*' >/dev/null
  assert_eq "renamed" "$(sh "$DST/tool")"
}

test_internet_tgz_installer_with_tar_options() {
  mkdir -p "$SRC/tree/pkg-2.0/lib"
  printf 'data\n' > "$SRC/tree/pkg-2.0/lib/data.txt"
  _make_tgz "$SRC/pkg-2.0.tgz" pkg-2.0
  internet_tgz_installer https://example.com/pkg-2.0.tgz "$DST" "" "" --strip-components=1
  assert_eq "data" "$(cat "$DST/lib/data.txt")"
  _assert_no_leftovers
}

test_internet_script_installer_with_shebang() {
  make_script "$SRC/install.sh" <<EOF
#!/bin/sh
echo "\$0 \$*" > "$TEST_TMPDIR/ran"
EOF
  internet_script_installer https://example.com/install.sh "" "" one two
  ran=$(cat "$TEST_TMPDIR/ran")
  assert_match "$ran" '/install\.[A-Za-z0-9]{6}\.sh one two$' "keeps extension, passes arguments"
  rm -f "$TEST_TMPDIR/ran"
  _assert_no_leftovers
}

test_internet_script_installer_without_shebang_uses_bash() {
  require_cmd bash
  printf 'echo "${BASH_VERSION:+bash}" > "%s/ran"\n' "$TEST_TMPDIR" > "$SRC/raw"
  internet_script_installer https://example.com/raw hook ""
  assert_eq "bash" "$(cat "$TEST_TMPDIR/ran")"
}

test_internet_script_installer_returns_script_status() {
  printf '#!/bin/sh\nexit 3\n' > "$SRC/fail.sh"
  rc=0
  internet_script_installer https://example.com/fail.sh "" "" || rc=$?
  assert_eq 3 "$rc"
}
