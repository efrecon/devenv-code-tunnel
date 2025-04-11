# dev environment in a container, tunneled by vscode

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

### Manually with `docker`

Build using the following command, this will create an image called
`code_tunnel`.

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
