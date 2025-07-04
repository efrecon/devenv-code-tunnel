# Tunneled dev environments in containers or microVMs

This project implements encapsulated development environments that run in
containers or microVMs. Environments are designed to be accessed through tunnels
(e.g., Visual Studio Code) and require `docker` or `podman` on the host, with
optional support for [`krun`][krun]. The following one-liner will create a
volume called `devenv` and restrict access to the `efrecon` user at GitHub.
Replace `efrecon` with your GitHub username. Audit the wrapper script
[here](./devenv.sh).

```bash
curl -fsSL https://raw.githubusercontent.com/efrecon/devenv-code-tunnel/main/devenv.sh | \
  sh -s - devenv -- -g efrecon
```

The environment will automatically establish two tunnels and provide access
instructions in the logs:

- One VS Code [tunnel][vscode]. For access, you will have to follow the link to
  authorize the tunnel while logged in as `efrecon` at GitHub.
- One [cloudflare] quick tunnel. Access from [cloudflare] is restricted to the
  public SSH keys registered under the `efrecon` account.

The [`devenv.sh`](./devenv.sh) wrapper script will prefer creating a fully
encapsulated microVM with `podman` and `krun`, but will fall back to privileged
containers on top of `podman` or `docker`, depending on which container solution
is installed and accessible. Containers need to be privileged in order for the
user inside the development environment to be able to run `docker`, a.k.a.
Docker-in-Docker ([DinD]).

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

- A volume named after the first argument (`devenv`) will be created if
  necessary and mounted into the development environment as the home directory
  for the user `coder`.
- The local container/VM will also be named after the first argument (e.g.,
  `devenv`). If there was an existing container running under that name, it will
  be removed.
- The VS Code tunnel will be called after `<hostname>-devenv`, where
  `<hostname>` will be the actual name of the host that the command is run on.
- The `-v` option will be passed to the entrypoint of the container, providing
  for more information in the logs of the container. You can pass any
  [option](#quick-options-tunnelsh-run-down) recognized by the entrypoint.

[image]: https://github.com/users/efrecon/packages/container/devenv-code-tunnel-alpine/421321230?tag=main

Quick start: run this one-liner to fetch [`devenv.sh`](./devenv.sh) directly
from GitHub. This example will only print the help through the `-h` option, but
you can specify any of the options described in the
[options](#quick-options-tunnelsh-run-down) section below.

```bash
curl -fsSL https://raw.githubusercontent.com/efrecon/devenv-code-tunnel/main/devenv.sh | \
  sh -s - -h
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

- `--privileged` is necessary, so the environment can easily run
  Docker-in-Docker ([DinD]).
- `--hostname` is required to avoid having to re-authorize the device tunnel
  each time the container starts -- as long as you use the same hostname. By
  default, the name of the tunnel will then be the same as the hostname.

### Quick Options `tunnel.sh` run-down

Inside the container, `tunnel.sh` is used to create the tunnel. The script takes
the following options.

- `-v` (repeat the `v`s) to increase verbosity
- `-n xx` to give a name to the tunnel, this will automatically attempt to set
  the hostname inside the container to the same name. Changing the hostname
  **requires** `--privileged`, a warning will be printed out elsewise. Setting
  the hostname is to avoid that the tunnel will think that it is running on a
  different device each time it is run.
- `-f` to force authorization of the device at the provider
- `-p` to change the provider away from the `github` default.
- `-k` to specify a hook that will automatically be downloaded and executed
  before the tunnel is started. You can use this to run a gist that would set up
  your environment and dotfiles, for example. To run this [gist], give its raw
  URL as a value, i.e.
  `https://gist.githubusercontent.com/efrecon/a9addf9f5812212366ede103bfc211f6/raw`
- `-g` is the name of a GitHub user (you?!) to allow for connecting into the
  tunnels.
- `-G` is the URL to a GIST that will be updated with details about the created
  tunnels. Under the root of that GIST, a file named after the name of the
  tunnel (with a `.txt` extension) will be maintained to store access details.
  For additional security, you should make that GIST private. This requires the
  `git` feature to be installed.
- `-s` is the port for the SSH server inside the container. The default is `2222`.
  This port will be used to connect to the container via SSH, and also to
  connect to the cloudflare tunnel.
- `-S` contains a space-separated list of [services](./share/services/README.md)
  to start inside the container. The default is to start all services. Specify a
  `-` to not start any service.
- `-T` selects the tunnels that are to be started, provided they have been
  installed in the image. The default is to start all tunnels.
- `-L` selects the logs to reprint inside the main container logs. Specify a `-`
  to not reprint anything.

[gist]: https://gist.github.com/efrecon/a9addf9f5812212366ede103bfc211f6

## Security

All traffic to and from the development environments and the clients is
encrypted using HTTPS. When running on top of cloudflare tunnels, traffic is
end-to-end encrypted using SSH.

- Access to the VS Code tunnel is restricted to the GitHub user passed through
  the `-g` option. On the first run, the tunnel will also have to be authorized
  at GitHub through the URL printed in the logs.
- Access to the cloudflare tunnel is restricted to the SSH keys that are stored
  under the GitHub user passed through the `-g` option.

When running using `krun`, the development environments are running inside micro
VMs and are encapsulated from the host. When running using `podman` or `docker`,
it is recommended to use the `--privileged` option. This is a security issue,
but is mandatory to be able to run a separate Docker daemon inside the
containers. The daemon will gracefully refuse to start whenever the container is
detected to not have enough privileges. It is possible to pass, e.g. the socket
of the Docker daemon running on the host to the containers.

## Official Images

Official images are published to the GitHub container [registry]. There are 4
images in total, based on either Alpine Linux or Debian. For the debian images,
replace `alpine` with `debian` in the image name below. The images are:

- `ghcr.io/efrecon/devenv-code-tunnel-alpine-minimal:main` provides a user
  called `coder`. The user can `sudo` without a password. Only the VS code CLI
  is installed.
- `ghcr.io/efrecon/devenv-code-tunnel-alpine:main` adds a number of
  (opinionated) software onto the image. The entire list is as per the content
  of the [features](./share/features/) directory.

[registry]: https://github.com/efrecon/devenv-code-tunnel/pkgs/container/devenv-code-tunnel-alpine
