# Internal Settings

The main [entrypoint] delegates the initialization of [services] and of
[tunnels], and these in turns use a number of helper scripts for
[orchestration]. When a file starting with the basename of one of the previously
mentioned scripts, followed by the `.env` extension is present in this
directory, it will automatically be sourced into the script. This allows to set
some semi-internal variables that would change the behavior of those scripts.

For example, to change the behavior of the `gist.sh` script, you would create a
`gist.env` file in this directory, and this file would set a number of variables
starting with the same basename, but in upper case, e.g. `GIST_`.

  [entrypoint]: ../tunnel.sh
  [services]: ./init.d/README.md
  [tunnels]: ../share/tunnels/README.md
  [orchestration]: ../share/orchestration/
