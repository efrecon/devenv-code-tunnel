# Services

Each file in this directory is run by the [entrypoint] at start, files are run
as per their ordering in order to manage dependencies, if any. These should be
standalone scripts, they *can* have options, but this is not recommended as they
will be started without options from the [entrypoint].

By design, options should be expressed through variables that start with the
basename of the service, in upper case, followed by an underscore; e.g.
`10-dockerd.sh` would have variables starting with `DOCKERD_`. These variables
will often inherit the value of variables coming from the [entrypoint]. The
variables in the entrypoint start with `TUNNEL_`, as per the same convention.

  [entrypoint]: ../../tunnel.sh
