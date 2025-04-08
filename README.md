# vscode tunnel environement in a container

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
docker run -it --rm --privileged -v home:/home/coder:Z code_tunnel -vv -n coding-guru
```

Notes:

+ `--privileged` is necessary so the environment will be able to easily run
  Docker in Docker.
+ The hostname inside the container will be overridden with the name of the
  tunnel. This is to ensure that you will be able to reuse device authentication
  each time. Use the `-f` option to force re-authorization of the device.
