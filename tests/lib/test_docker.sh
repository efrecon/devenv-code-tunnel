#!/bin/sh
# shellcheck disable=SC2016,SC2034 # Variables are read by the libraries and in wait_until
# Tests for lib/docker.sh

setup() {
  load_lib log common system docker
}

test_is_podman_container_from_variable() {
  container=podman
  assert_true is_podman_container
}

test_is_podman_container_otherwise() {
  [ -f /run/.containerenv ] && skip "running in a podman container"
  container=docker
  assert_false is_podman_container
  unset container
  assert_false is_podman_container
}

test_is_privileged_matches_capabilities() {
  [ -r /proc/self/status ] || skip "no /proc"
  [ -r /proc/sys/kernel/cap_last_cap ] || skip "no capabilities information"
  # All capabilities up to the last one are in the bounding set when privileged.
  bnd=$(sed -n 's/^CapBnd:[[:space:]]*//p' /proc/self/status)
  last=$(cat /proc/sys/kernel/cap_last_cap)
  full=$(printf '%x' "$(( (1 << (last + 1)) - 1 ))")
  if [ "$(printf '%x' "0x$bnd")" = "$full" ]; then
    assert_true is_privileged
  else
    assert_false is_privileged
  fi
}
