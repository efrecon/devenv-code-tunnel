# Tests

Tests for the shared libraries in [`lib`](../lib/),
the orchestration tools in [`share/orchestration`](../share/orchestration/),
the tunnel scripts in [`share/tunnels`](../share/tunnels/) and [`devenv.sh`](../devenv.sh),
plus a smoke test of the built images.
Installation scripts (`share/features`) are not tested here: they run every time an image is built.

The tests are plain POSIX shell, so they run with the same shells and tools as the images:
busybox on Alpine, dash and GNU tools on Debian and Ubuntu.
They run at GitHub for every pull request, in all three distributions,
see [`tests.yml`](../.github/workflows/tests.yml).

## Running

```bash
tests/run.sh                      # all tests, with sh
tests/run.sh wait: lwrap          # tests which <file>:<function> matches a filter
tests/run.sh -s bash -v           # run with bash, print the output of all tests
tests/run.sh -s 'bash --posix'    # run with bash in POSIX mode
```

`-s` only changes the shell running the tests and the orchestration scripts they call.
Scripts that these call in turn use their `#!/bin/sh` line.
At GitHub, one job makes `/bin/sh` point to bash, so that everything runs in the POSIX mode of bash,
which bash enters when invoked as `sh`.

To run as at GitHub, in one of the distributions:

```bash
docker run --rm --init -v "$PWD:/src:ro" -w /src alpine:3.24 \
  sh -c 'apk add -q git logrotate inotify-tools bash && tests/run.sh'
```

Tests needing a missing tool (`git`, `logrotate`, `bash`) are skipped.
Tests needing root are skipped unless run as root.
As root, they create user accounts and install a package, which can remain after the run:
only run the tests as root in a disposable container, as above.

## What is tested where

| Directory                          | What                                                                 |
|------------------------------------|----------------------------------------------------------------------|
| [`lib`](lib/)                      | Shared libraries. Tests needing root (users, packages) are skipped unless run as root, as in the containers at GitHub. |
| [`orchestration`](orchestration/)  | Orchestration tools, run as separate processes.                      |
| [`tunnels`](tunnels/)              | Tunnel scripts, against fake `code`, `cloudflared`, `tailcat` and `nc` commands. |
| [`devenv`](devenv/)                | `devenv.sh`, against fake `docker`, `podman` and `msb` commands.      |
| [`smoke.sh`](smoke.sh)             | Not a unit test: starts a built image and checks it runs. Called for each platform when building images, before they get tagged. |

```bash
tests/smoke.sh ghcr.io/efrecon/devenv-code-tunnel-alpine:main
```

Tests using fake commands restrict `PATH` to the system directories.
When a real tool is installed there, tests that need it to be absent are skipped,
they will never run against a real orchestrator or tunnel.

All shell scripts are also linted with [shellcheck] for every pull request.

[shellcheck]: https://www.shellcheck.net/

## Writing tests

- Test files are named `test_*.sh` and placed in the directory mirroring what they test,
  e.g. `tests/lib/test_wait.sh` for `lib/wait.sh`.
- Each function named `test_*` is a test.
  It runs in its own shell process, with `set -eu`,
  in an empty temporary directory that is also `TMPDIR` and `TEST_TMPDIR`.
  A `setup` function, when present, runs before each test.
- The temporary directory does not isolate changes to the system itself.
  As root, and with the user tools available (`adduser`, `chpasswd`, `getent`, `su`),
  tests marked with `require_root` create user accounts with their home directories, which are never removed,
  and the `.deb` test installs a package, which stays installed when the test fails before removing it.
  Run tests as root only in a disposable container, as shown above, never directly on a host you care about.
- `TUNNEL_` variables of the caller are removed and `TUNNEL_PREFIX` points into the temporary directory,
  so logs from orchestration tools stay there.
- Helpers and assertions are in [`framework/harness.sh`](framework/harness.sh):
  `load_lib`, `run_orchestration`, `run_script`, `fake_path`, `fake_cmd`, `assert_eq <expected> <actual>`,
  `assert_match`, `assert_contains`, `assert_fails`, `wait_until`, `skip`, `require_root`, etc.
- Pass the code to `wait_until` in single quotes, so it is evaluated at each try: `wait_until 5 '[ "$(count)" -ge 1 ]'`.
- Stop the background processes a test starts, e.g. with `kill_tree` from `lib/system.sh`.
