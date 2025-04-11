# Contributing

## Building with Less Features

When devloping a new features, it is possible to use build arguments to select a
subset of the features to install. This will speed up the build, as the default
installs many packages and software. For example, the following would only
install the `sudo` and `codecli` feature.

```bash
docker build \
  -t code_tunnel_minimal \
  --build-arg 'INSTALL_FEATURES=sudo codecli' \
  .
```
