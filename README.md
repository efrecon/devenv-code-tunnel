# Tunneled dev environments in containers or microVMs

This project implements encapsulated development environments to be run in
containers or microVMs. Environments are designed to be accessed through tunnels
from, e.g. Visual Studio Code. Provided you have `docker` or `podman` installed
on a host -- and perhaps [`krun`][krun] -- the following one-liner will create a
volume called `devenv` and restrict access to the `efrecon` user at GitHub. Feel
free to change to your username! You can audit the wrapper script
[here](./devenv.sh).

```bash
curl -fsSL https://raw.githubusercontent.com/efrecon/devenv-code-tunnel/main/devenv.sh | \
  sh -s - devenv -- -g efrecon
```

The environment will automatically establish two tunnels and provide access
instructions in the logs:

- one vscode [tunnel][vscode]. For access, you will have to follow the link to
authorize the tunnel while logged in as `efrecon` at GitHub.
- one [cloudflare] quick tunnel. Access from [cloudflare] is restricted
to the public SSH keys registered under the `efrecon` account.

The [`devenv.sh`](./devenv.sh) wrapper script will prefer creating a fully
encapsulated microVM with `podman` and `krun`, but will gracefully downgrade to
privileged containers on top of `podman` or `docker`, depending on which
container solution is installed and accessible. The containers need to be
privileged in order for the user inside the development environment to be able
to run `docker`, a.k.a. [DinD] or docker in docker.

The [`devenv.sh`](./devenv.sh) wrapper script automatically uses a "fat" image
based on Alpine Linux. The content of this image is controlled through a set of
high-level [features](./share/features/README.md). To tune the content of your
environment, for example to remove features or change the base image, you can
control its content through build arguments via the
[command-line](#manually-with-docker) or [compose](#with-compose).

[krun]: https://github.com/containers/crun/blob/main/krun.1.md
[vscode]: https://code.visualstudio.com/docs/remote/tunnels
[cloudflare]: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/do-more-with-tunnels/trycloudflare/
[DinD]: https://www.docker.com/resources/docker-in-docker-containerized-ci-workflows-dockercon-2023/

## Usage

### With `compose`

Run the following command to get a tunnel with a random name, using the `github`
provider:

```bash
docker compose up
```

Watch the logs, and authorize the device as per the instructions. Once your
tunnel has been authorized, the logs will print out a URL to access the tunnel
from your browser.

You can set the environment variable `TUNNEL_NAME` to choose the name of your
tunnel.

### Using the Standalone Helper

The standalone helper aims at quickly creating isolated development environments
based on the images created by this project. It uses sensible defaults and, when
possible, will prefer microVMs using podman's [krun]. Start by making sure
[`devenv.sh`](devenv.sh) is accessible from your `$PATH`. Run the following to
create a development environment with the all-inclusive official [image].

```bash
devenv.sh devenv -v
```

This will create a (privileged) container or VM, running in the foreground and
offering these features:

+ A volume named after the first argument, `devenv` will be created, if
  necessary and mounted into the development environment as the home directory
  for the user `coder`.
+ The local container/VM will also be named after the first argument (e.g.
  `devenv`). If there was an existing container running under that name, it will
  be removed.
+ The vscode tunnel will be called after `<hostname>-devenv`, where `<hostname>`
  will be the actual name of the host that the command is run on.
+ The `-v` option will be passed to the entrypoint of the container, providing
  for more information in the logs of the container. You can pass any
  [option](#quick-options-tunnelsh-run-down) recognized by the entrypoint.

[image]: https://github.com/users/efrecon/packages/container/devenv-code-tunnel-alpine/421321230?tag=main

Even more in a hurry? Run the following one liner to run `devenv.sh` directly
from GitHub. This example will only print the help through the `-h` option.

```bash
curl -sSL https://raw.githubusercontent.com/efrecon/devenv-code-tunnel/refs/heads/main/devenv.sh | sh -s - -h
```

### Manually with `docker`

Build using the following command, this will create an image called
`code_tunnel`. You can switch `docker` to `podman` if you prefer; both
containerization technologies work interchangeably.

```bash
docker build -t code_tunnel .
```

Create a volume for your home

```bash
docker volume create home
```

Create a container, giving the tunnel the name `a-name-of-your-choice`

```bash
docker run \
  -it \
  --rm \
  --privileged \
  --hostname "a-name-of-your-choice" \
  -v home:/home/coder:Z \
  code_tunnel \
    -vv
```

Do as above, i.e. watch the logs for how to authorize at `github`, and then how
to access your container from your browser.

Notes:

+ `--privileged` is necessary so the environment will be able to easily run
  Docker in Docker.
+ `--hostname` is necessary in order to avoid to have to re-authorize the device
  tunnel each time the container starts -- as long as you use the same hostname.
  By default, the name of the tunnel will then be the same as the hostname.

### Quick Options `tunnel.sh` run-down

Inside the container, `tunnel.sh` is used to create the tunnel. The script takes
the following options.

+ `-v` (repeat the `v`s) to increase verbosity
+ `-n xx` to give a name to the tunnel, this will automatically attempt to set
  the hostname inside the container to the same name. Changing the hostname
  **requires** `--privileged`, a warning will be printed out elsewise. Setting
  the hostname is to avoid that the tunnel will think that it is running on a
  different device each time it is run.
+ `-f` to force authorization of the device at the provider
+ `-p` to change the provider away from the `github` default.
+ `-k` to specify a hook that will automatically be downloaded and executed
  before the tunnel is started. You can use this to run a gist that would setup
  your environment and dotfiles, for example. To run this [gist], give its raw
  URL as a value, i.e.
  `https://gist.githubusercontent.com/efrecon/a9addf9f5812212366ede103bfc211f6/raw`
+ `-g` is the name of a GitHub user (you?!) to allow for connecting into the
  cloudflare tunnel via SSH.
+ `-G` is the URL to a GIST that will be updated with details about the created
  tunnels. Under the root of that GIST, a file named after the name of the
  tunnel, with the `.txt` extension will be maintained with access content. For
  additional security, you should make that GIST private. This requires the
  `git` feature to be installed.
+ `-T` selects the tunnels that are to be started, provided they have been
  installed in the image. The default is to start all tunnels.
+ `-L` selects the logs to reprint inside the main container logs. Specify a `-`
  to not reprint anything.

[gist]: https://gist.github.com/efrecon/a9addf9f5812212366ede103bfc211f6

## Official Images

Official images are published to the GitHub container [registry]. There are two
images:

+ `ghcr.io/efrecon/devenv-code-tunnel-alpine-minimal:main` provides a user
  called `coder`. The user is able to `sudo` without password. Only the vscode
  CLI is installed.
+ `ghcr.io/efrecon/devenv-code-tunnel-alpine:main` adds a number of
  (opinionated) software onto the image. The entire list is as per the content
  of the [features](./share/features/) directory.

[registry]: https://github.com/efrecon/devenv-code-tunnel/pkgs/container/devenv-code-tunnel-alpine
