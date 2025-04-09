# vscode tunnel environment in a container

## Usage

Build using the following command

```bash
docker build -t code_tunnel .
```

Create a volume for your home

```bash
docker volume create home
```

Create a container, giving the tunnel the name `coding-guru`

```bash
docker run \
  -it \
  --rm \
  --privileged \
  -v home:/home/coder:Z \
  code_tunnel \
    -vv \
    -n coding-guru
```

Notes:

+ `--privileged` is necessary so the environment will be able to easily run
  Docker in Docker.
+ The hostname inside the container will be overridden with the name of the
  tunnel. This is to ensure that you will be able to reuse device authentication
  each time. Use the `-f` option to force re-authorization of the device.

### Quick Options run-down

+ `-vv` (repeat the `v`s) to increase verbosity
+ `-n xx` to give a name to the tunnel, this will automatically set the hostname
  inside the container to the same name -- unless you had set it from the
  outside `docker run` command. This is to avoid that the tunnel will think that
  it is running on a different device each time you run.
+ `-f` to force authorization of the device at the provider
+ `-p` to change the provider away from the `github` default.
+ `-k` to specify a hook that will automatically be downloaded and executed
  before the tunnel is started. You can use this to run a gist that would setup
  your environment and dotfiles, for example. To run this [gist], give its raw
  URL as a value, i.e.
  `https://gist.githubusercontent.com/efrecon/a9addf9f5812212366ede103bfc211f6/raw`

  [gist]: https://gist.github.com/efrecon/a9addf9f5812212366ede103bfc211f6

## Official Images

Official images are published to the GitHub container [registry].

  [registry]: https://github.com/efrecon/devenv-code-tunnel/pkgs/container/devenv-code-tunnel-alpine
