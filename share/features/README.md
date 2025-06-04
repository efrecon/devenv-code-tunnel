# Feature Installers

Each script in this directory is used by the main [install.sh][install] script
to install features in the Docker images. These scripts are standalone scripts,
but will inherit some of the `INSTALL_` environment variables set from the main
script. Many of these scripts will have more variables starting with `INSTALL_`
to express, for example, optional features or specific versions to install. As
all `INSTALL_`-led variables will be inherited from the main [install] script,
this means that it is possible -- and recommended -- to set and pass these
variables at buildtime through the Dockerfile.

  [install]: ../../build/install.sh
