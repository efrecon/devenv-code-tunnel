# OS-Specific Overlays

This directory contains hierarchies that will automatically be added to the root
file system of the Docker image. There should be one directory per base
operating system, e.g. [alpin](./alpine/). The content of these hierarchies will
be added as `root`.
