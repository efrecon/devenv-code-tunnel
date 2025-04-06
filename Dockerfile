FROM alpine:3.21.3


# Where to install our own stuff.
ARG INSTALL_PREFIX=/usr/local

# Become root to be able to perform installation operations.
USER root

COPY *.sh ${INSTALL_PREFIX}/bin/
COPY lib/*.sh ${INSTALL_PREFIX}/lib/
COPY share/features/*.sh ${INSTALL_PREFIX}/share/features/
COPY etc/init.d/*.sh ${INSTALL_PREFIX}/etc/init.d/

VOLUME /home/coder
RUN chmod a+x ${INSTALL_PREFIX}/bin/*.sh && \
    ${INSTALL_PREFIX}/bin/install.sh -vv -u coder && \
    ${INSTALL_PREFIX}/bin/hotfix.sh -vv

USER coder
ENTRYPOINT [ "tunnel.sh" ]

