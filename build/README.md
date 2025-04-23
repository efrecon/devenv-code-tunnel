# Build Scripts

These scripts are used as `RUN` commands to build the content of the Docker
images. By design, the content of the Dockerfile is kept to a minimum and most
of the installation process is handled by these scripts. This allows to run the
scripts in different context, e.g. manually on a virtual machine -- or similar.
