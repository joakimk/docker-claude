# Generic Claude Code container.
#
# FROM any base image (set via BASE_IMAGE build arg) and layers on:
#   - Claude Code CLI (installed for the unprivileged dev user)
#   - Firewall tooling (iptables, ipset, dig) so init-firewall.sh works
#   - An entrypoint that sets up the firewall, drops to dev, execs claude
#
# The base image is expected to provide whatever project toolchain is
# needed (rust, python, node, etc.). Configure BASE_IMAGE in the
# project's docker-claude.config. For projects whose toolchain is
# already baked into their own image, set BASE_IMAGE to that image
# name and set BASE_IMAGE_CONTEXT in the config so run.sh builds it
# first.

ARG BASE_IMAGE=debian:bookworm-slim
FROM ${BASE_IMAGE}

USER root

# Packages the firewall and Claude need. bsdmainutils is optional
# convenience (column/hexdump); drop if image-size conscious.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        iptables \
        iproute2 \
        dnsutils \
        tmux \
    && rm -rf /var/lib/apt/lists/*

# Match container user to host UID/GID so bind mounts are writable
# without root. Build args default to 1000/1000; run.sh passes the
# host's actual id. If the base image already defines user "dev", we
# reuse it; otherwise we create it.
ARG HOST_UID=1000
ARG HOST_GID=1000
RUN if ! id -u dev >/dev/null 2>&1; then \
        getent group "${HOST_GID}" >/dev/null || groupadd -g "${HOST_GID}" dev ; \
        useradd -m -u "${HOST_UID}" -g "${HOST_GID}" -s /bin/bash dev ; \
    fi

# Claude Code installs to $HOME/.claude/local, so install as dev.
USER dev
RUN curl -fsSL https://claude.ai/install.sh | bash
USER root

# Make git trust any workspace regardless of mount ownership.
RUN git config --system --add safe.directory '*'

# Firewall + entrypoint. Strip CRLFs in case the scripts were edited
# on a Windows host before being copied in.
COPY init-firewall.sh entrypoint.sh /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh \
    && chmod 0755 /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh

# Claude on dev's PATH for both login and non-login shells.
RUN printf 'export PATH="$HOME/.claude/local/bin:$PATH"\n' >> /home/dev/.profile \
    && sed -i '1i export PATH="$HOME/.claude/local/bin:$PATH"' /home/dev/.bashrc

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
