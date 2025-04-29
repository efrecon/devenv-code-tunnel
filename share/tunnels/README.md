# Tunnel Helpers

This directory contains scripts that are used by the main
[`tunnel.sh`](../../tunnel.sh) script -- the entrypoint of the Docker image --
to create tunnels for the various services that are supported by this project.
These scripts will inherit the `TUNNEL_` variables, in case they needed to
understand better their environment and CLI requests. Apart from that, each
script is standalone, has good defaults, and can be run separately.
