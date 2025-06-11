ARG INSTALL_IMAGE=alpine:3.22.0
FROM ${INSTALL_IMAGE}


# Where to install our own stuff.
ARG INSTALL_PREFIX=/usr/local

# What to install, default is everything
ARG INSTALL_FEATURES=

# Name of the user and group to create
ARG INSTALL_USER=coder
ARG INSTALL_GROUP=${INSTALL_USER}

# Versions and channels to pick features from, when applicable. Some features
# rely on the latest available package(s) as of the version of the OS.

# Build of vscode to install: only stable or insiders are available.
ARG INSTALL_CODE_BUILD=stable
ARG INSTALL_CLOUDFLARED_VERSION=2025.5.0
# Version of Node.js to install. Empty to disable. This will match as much as
# you want, e.g. 10 or 10.12, etc.
ARG INSTALL_NODE_VERSION=22
# Type of the builds to download. rc or release.
ARG INSTALL_NODE_TYPE=release
# Version of .NET to install. Empty to disable. STS, LTS, 2-hand, 3-hand
# versions
ARG INSTALL_DOTNET_CHANNEL=8.0
# Quality for the current channel.
ARG INSTALL_DOTNET_QUALITY=GA
# Version of Powershell to install
ARG INSTALL_POWERSHELL_VERSION=7.5.1
ARG INSTALL_GITHUB_VERSION=2.73.0
ARG INSTALL_GITLAB_VERSION=1.57.0
ARG INSTALL_TEA_VERSION=0.9.2


# Become root to be able to perform installation operations.
USER root

# Copy installation scripts and files.
COPY lib/*.sh ${INSTALL_PREFIX}/lib/
COPY build/*.sh ${INSTALL_PREFIX}/bin/
COPY share/features/*.sh ${INSTALL_PREFIX}/share/features/

VOLUME /home/${INSTALL_USER}
RUN chmod a+x ${INSTALL_PREFIX}/bin/*.sh && \
    INSTALL_CODE_BUILD=${INSTALL_CODE_BUILD} \
    INSTALL_CLOUDFLARED_VERSION=${INSTALL_CLOUDFLARED_VERSION} \
    INSTALL_NODE_VERSION=${INSTALL_NODE_VERSION} \
    INSTALL_NODE_TYPE=${INSTALL_NODE_TYPE} \
    INSTALL_DOTNET_CHANNEL=${INSTALL_DOTNET_CHANNEL} \
    INSTALL_DOTNET_QUALITY=${INSTALL_DOTNET_QUALITY} \
    INSTALL_POWERSHELL_VERSION=${INSTALL_POWERSHELL_VERSION} \
    INSTALL_GITHUB_VERSION=${INSTALL_GITHUB_VERSION} \
    INSTALL_GITLAB_VERSION=${INSTALL_GITLAB_VERSION} \
    INSTALL_TEA_VERSION=${INSTALL_TEA_VERSION} \
    CODER_INTERACTIVE=1 \
        ${INSTALL_PREFIX}/bin/install.sh \
            -vvv \
            -u "${INSTALL_USER}:${INSTALL_GROUP}" && \
    CODER_INTERACTIVE=1 ${INSTALL_PREFIX}/bin/hotfix.sh -v

# Copy the init scripts and other files.
COPY *.sh ${INSTALL_PREFIX}/bin/
COPY etc/*.env ${INSTALL_PREFIX}/etc/
COPY etc/init.d/*.sh ${INSTALL_PREFIX}/etc/init.d/
COPY share/tunnels/*.sh ${INSTALL_PREFIX}/share/tunnels/
COPY share/orchestration/*.sh ${INSTALL_PREFIX}/share/orchestration/

# Overlay the rootfs with our own stuff.
COPY rootfs/alpine/ /

USER ${INSTALL_USER}
WORKDIR /home/${INSTALL_USER}
ENV ENV=/etc/.shinit
ENV BASH_ENV=/etc/.shinit

EXPOSE 2222

# Run behind tini, capturing the entire process group to properly teardown all
# subprocesses.
STOPSIGNAL SIGINT
ENTRYPOINT [ "tini", "-vs", "--", "tunnel.sh" ]
