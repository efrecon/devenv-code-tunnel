# Tunneled dev environments in containers or microVMs

This project implements encapsulated development environments that run in microVMs or containers.
Environments are designed to be accessed from anywhere through tunnels (e.g., Visual Studio Code).
They require [`msb`][msb], `docker` or `podman` on the host, with optional support for [`krun`][krun].
The following one-liner will create a volume called `devenv` and restrict access to the `efrecon` user at GitHub.
Replace `efrecon` with your GitHub username.
Feel free to audit the [wrapper script](./devenv.sh).

```bash
curl -fsSL https://raw.githubusercontent.com/efrecon/devenv-code-tunnel/main/devenv.sh | \
  sh -s - devenv -- -g efrecon
```

The environment will automatically establish 3 tunnels and provide access instructions in the logs:

- One VS Code [tunnel][vscode].
  For access, you will have to follow the link to authorize the tunnel while logged in as `efrecon` at GitHub.
- One [cloudflare] quick tunnel.
  Access through Cloudflare is restricted to the public SSH keys registered under the `efrecon` account.
- One [tailcat] tunnel.
  Access through Tailscale is restricted to the public SSH keys registered under the `efrecon` account.

The [`devenv.sh`](./devenv.sh) wrapper script will prefer creating a fully isolated sandbox with `msb`,
otherwise a fully encapsulated microVM with `podman` and `krun`,
but will fall back to privileged containers on top of `podman` or `docker`,
depending on which container/sandboxing solution is installed and accessible.
Containers need to be privileged in order for the user inside the development environment to be able to run `docker`,
a.k.a. Docker-in-Docker ([DinD]).

The [`devenv.sh`](./devenv.sh) wrapper script automatically uses a "fat" image based on Alpine Linux.
The content of this image is controlled through a set of high-level [features](./share/features/README.md).
To tune the content of your environment, for example to remove features or change the base image,
you can control its content through build arguments via the [command-line](#manually-with-docker) or [compose](#with-compose).

[msb]: https://github.com/superradcompany/microsandbox
[krun]: https://github.com/containers/crun/blob/main/krun.1.md
[vscode]: https://code.visualstudio.com/docs/remote/tunnels
[cloudflare]: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/do-more-with-tunnels/trycloudflare/
[tailcat]: https://github.com/tailscale/tailcat
[DinD]: https://www.docker.com/resources/docker-in-docker-containerized-ci-workflows-dockercon-2023/

## Usage

### Using the Standalone Helper

The standalone helper aims at quickly creating isolated development environments based on the images created by this project.
It uses sensible defaults and, when possible, will prefer microVMs using first `msb`, otherwise podman's [krun].
Start by making sure [`devenv.sh`](devenv.sh) is accessible from your `$PATH`.
Run the following to create a development environment with the all-inclusive official [image].

```bash
devenv.sh devenv -v
```

This will create a VM or (privileged) container,
running in the foreground and offering these features:

- A volume named after the first argument (`devenv`) will be created if necessary
  and mounted into the development environment as the home directory for the user `coder`.
- The local container/VM will also be named after the first argument (e.g., `devenv`).
  If there was an existing container running under that name, it will be removed.
- The VS Code tunnel will be called after `<hostname>-devenv`,
  where `<hostname>` will be the actual name of the host that the command is run on.
- When the [`gh`][gh] CLI is installed and logged in on the host,
  its token is passed to the environment so that `git` and `gh` work at GitHub without logging in again,
  see [GitHub Authentication](#github-authentication).
  Use `-T` to pass another token, or `-T -` to pass none.
- Your private SSH key, best guess from `$HOME/.ssh`, is also passed to the environment.
  Use `-i` to pass another key, or `-i -` to pass none.
- The `-v` option will be passed to the entrypoint of the container, providing for more information in the logs of the container.
  You can pass any [option](#quick-options-tunnelsh-run-down) recognized by the [entrypoint](#quick-options-tunnelsh-run-down).
- First RC file found will have been sourced.
  Variable starting with `DEVENV_` control the behaviour of `devenv.sh`.
  Variable starting with `TUNNEL_` are automatically passed to the entrypoint.
  RC files are looked at:
  - $XDG_CONFIG_HOME/devenvrc
  - $HOME/.devenvrc
  - $(pwd)/.devenvrc
  - /etc/devenvrc
  - /usr/local/etc/devenvrc

[image]: https://github.com/users/efrecon/packages/container/devenv-code-tunnel-alpine/421321230?tag=main
[gh]: https://cli.github.com/

Quick start: run this one-liner to fetch [`devenv.sh`](./devenv.sh) directly from GitHub.
This example will only print the help through the `-h` option,
but you can specify any of the options described in the [options](#quick-options-tunnelsh-run-down) section below.

```bash
curl -fsSL https://raw.githubusercontent.com/efrecon/devenv-code-tunnel/main/devenv.sh | \
  sh -s - -h
```

### With `compose`

Run the following command to get a tunnel with a random name, using the `github` provider:

```bash
docker compose up
```

Watch the logs, and authorize the device as per the instructions.
Once your tunnel has been authorized,
the logs will print out a URL to access the tunnel from your browser.

You can set the environment variable `TUNNEL_NAME` to choose the name of your tunnel.

### Manually with `docker`

Build using the following command, this will create an image called `code_tunnel`.
You can switch `docker` to `podman` if you prefer;
both containerization technologies work interchangeably.

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

Do as above, i.e. watch the logs for how to authorize at `github`,
and then how to access your container from your browser.

Notes:

- `--privileged` is necessary, so the environment can easily run Docker-in-Docker ([DinD]).
- `--hostname` is required to avoid having to re-authorize the device tunnel each time the container starts
  -- as long as you use the same hostname.
  By default, the name of the tunnel will then be the same as the hostname.

### Quick Options `tunnel.sh` run-down

Inside the container, `tunnel.sh` is used to create the tunnel.
The script takes the following options.

- `-v` (repeat the `v`s) to increase verbosity
- `-n xx` to give a name to the tunnel,
  this will automatically attempt to set the hostname inside the container to the same name.
  Changing the hostname **requires** `--privileged`, a warning will be printed out elsewise.
  Setting the hostname is to avoid that the tunnel will think that it is running on a different device each time it is run.
- `-f` to force authorization of the device at the provider.
- `-p` to change the provider away from the `github` default.
- `-k` to specify a hook that will automatically be downloaded and executed before the tunnel is started.
  You can use this to run a gist that would set up your environment and dotfiles, for example.
  To run this [gist], give its raw URL as a value, i.e.
  `https://gist.githubusercontent.com/efrecon/a9addf9f5812212366ede103bfc211f6/raw`
- `-g` is the name of a GitHub user (you?!) to allow for connecting into the tunnels.
- `-G` is the URL to a GIST that will be updated with details about the created tunnels.
  Under the root of that GIST,
  a file named after the name of the tunnel (with a `.txt` extension) will be maintained to store access details.
  For additional security, you should make that GIST private.
  This requires the `git` feature to be installed.
  Both SSH (`git@gist.github.com:<id>.git`) and HTTPS (`https://gist.github.com/<id>.git`) clone URLs are accepted.
  Pushing requires either a [GitHub token](#github-authentication) with access to gists,
  or an SSH key registered at GitHub.
- `-s` is the port for the SSH server inside the container.
  The default is `2222`.
  This port will be used to connect to the container via SSH, and also to connect to the cloudflare tunnel.
- `-S` contains a space-separated list of [services](./share/services/README.md) to start inside the container.
  The default is to start all services.
  Specify a `-` to not start any service.
- `-T` selects the tunnels that are to be started, provided they have been installed in the image.
  The default is to start all tunnels.
- `-L` selects the logs to reprint inside the main container logs.
  Specify a `-` to not reprint anything.

[gist]: https://gist.github.com/efrecon/a9addf9f5812212366ede103bfc211f6

### GitHub Authentication

A GitHub token can be passed to the environment,
so that you can `git clone`, `git push` and use `gh` against GitHub without having to log in again,
and so that the [gist](#quick-options-tunnelsh-run-down) given to `-G` can be updated.

#### Passing the Token

[`devenv.sh`](./devenv.sh) picks the token as follows:

- By default, it uses the token of the [`gh`][gh] CLI on the host, i.e. the output of `gh auth token`,
  when `gh` is installed and logged in at `github.com`.
- `-T <token>` (or `DEVENV_GITHUB_TOKEN`) passes another token,
  either the token itself or the path to a file containing it.
- `-T -` passes no token at all.
  This also prevents a `TUNNEL_GITHUB_TOKEN` variable from being passed to the environment.

A token given as a value is stored, readable by you only, under `$XDG_STATE_HOME/devenv/<name>/github-token`
(`~/.local/state/devenv/<name>/github-token` by default),
where `<name>` is the name of the environment.
The file is mounted read-only at `/run/secrets/github-token` inside the environment,
which keeps the token out of the output of `docker inspect` or `podman inspect`.

When not using `devenv.sh`, e.g. with `docker run` or `compose`,
mount a file containing the token at `/run/secrets/github-token`,
or set the `TUNNEL_GITHUB_TOKEN` environment variable.
The variable takes precedence over the file,
and `TUNNEL_GITHUB_TOKEN_FILE` changes the location of the file.

#### Inside the Environment

At start, the github [service](./etc/init.d/35-github.sh):

- Copies the token to `/usr/local/etc/github/token`, readable by the `coder` user only.
  The token is purposely **not** stored in the home directory,
  as the home directory is often a directory of the host:
  it could end up in one of your projects.
  For the same reason, avoid `gh auth login` and `git credential-store` inside the environment.
- Configures `git` (`/etc/gitconfig`) with a credential helper that presents the token to `github.com` and `gist.github.com`.
  Other forges are not affected.
- Exports the token as `GH_TOKEN`, so `gh` works out of the box,
  both in terminals opened through the VS Code tunnel and in SSH sessions.
- When no private SSH key was passed (`-i -`),
  rewrites SSH URLs at GitHub, e.g. `git@github.com:owner/repo.git`, to HTTPS,
  so that SSH URLs, including those of existing clones in the home directory, keep working.
  When an SSH key was passed, SSH URLs are left untouched and use the key.

#### Permissions

The token needs the following permissions:
cloning and pushing to repositories, reading organizations for `gh`, and,
when using `-G`, writing to gists.

| Token                         | Permissions                                                                                                                                                                       |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `gh` CLI (default)            | `repo`, `read:org` and `gist` by default. Run `gh auth refresh -s workflow` on the host to be able to push changes to GitHub Actions workflows.                                    |
| Classic personal access token | `repo`, `read:org`, `gist`, and `workflow` to push changes to workflows.                                                                                                          |
| Fine-grained access token     | Repository permissions: *Contents* (read and write), *Metadata* (read), and as needed *Pull requests*, *Issues* and *Workflows*. Account permissions: *Gists* (read and write). |

Notes:

- Fine-grained tokens only give access to the repositories of a single owner (you, or one organization),
  and organizations might have to approve them.
  Classic tokens and the `gh` token give access to all repositories you can access.
- Organizations using SAML single sign-on require classic tokens to be [authorized][sso] for each organization.
- Prefer tokens with an expiration date and only the permissions you need.
  Unlike the token of the `gh` CLI, they can be revoked without affecting your host.

[sso]: https://docs.github.com/en/enterprise-cloud@latest/authentication/authenticating-with-saml-single-sign-on/authorizing-a-personal-access-token-for-use-with-saml-single-sign-on

## Security

All traffic to and from the development environments and the clients is encrypted using HTTPS.
When running on top of [cloudflare] and [tailcat] tunnels, traffic is end-to-end encrypted using SSH.

- Access to the VS Code tunnel is restricted to the GitHub user passed through the `-g` option.
  On the first run, the tunnel will also have to be authorized at GitHub through the URL printed in the logs.
- Access to the cloudflare and tailcat tunnels is restricted to the SSH keys that are stored under the GitHub user passed through the `-g` option.

When running using `msb` or `krun`, the development environments are running inside microVMs and are encapsulated from the host.
When running using `podman` or `docker`, it is recommended to use the `--privileged` option.
This is a security issue, but is mandatory to be able to run a separate Docker daemon inside the containers.
The daemon will gracefully refuse to start whenever the container is detected to not have enough privileges.
It is possible to pass, e.g. the socket of the Docker daemon running on the host to the containers.

By default, your GitHub token and your private SSH key are passed to the environments.
Any process running in an environment, e.g. package installation scripts, editor extensions or AI agents,
can read them and act as you at GitHub.
Use `-T -` and `-i -` to pass neither,
or pass a [token](#github-authentication) restricted to what the environment needs.

## Official Images

Official images are published to the GitHub container [registry].
There are 4 images in total, based on either Alpine Linux or Debian.
For the debian images, replace `alpine` with `debian` in the image name below.
The images are:

- `ghcr.io/efrecon/devenv-code-tunnel-alpine-minimal:main` provides a user called `coder`.
  The user can `sudo` without a password.
  Only the VS code CLI is installed.
- `ghcr.io/efrecon/devenv-code-tunnel-alpine:main` adds a number of (opinionated) software onto the image.
  The entire list is as per the content of the [features](./share/features/) directory.

[registry]: https://github.com/efrecon/devenv-code-tunnel/pkgs/container/devenv-code-tunnel-alpine
