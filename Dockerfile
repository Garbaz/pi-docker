# =============================================================================
# Pi Coding Agent — Base Docker Image
# =============================================================================
# This is the base image for running Pi in an isolated container.
# Projects can extend this by creating a Dockerfile.extend in their project root
# that starts with:  FROM pi-base:latest
#
# Build:  docker build -t pi-base:latest /home/tobi/.pi/docker
# =============================================================================

FROM node:22.22-slim AS base

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system essentials that Pi and common dev workflows need
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    ca-certificates \
    gnupg \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    jq \
    ripgrep \
    fd-find \
    unzip \
    bash-completion \
    less \
    vim \
    nano \
    procps \
    openssh-client \
    sudo \
    patch \
    file \
    pkg-config \
    locales \
    && rm -rf /var/lib/apt/lists/*

# fd-find installs as 'fdfind' — symlink to 'fd' so agents find it by the expected name
# python3 is the binary — symlink 'python' so agents find it without the 3 suffix
RUN ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && ln -s /usr/bin/python3 /usr/local/bin/python

# Set up UTF-8 locale (many tools break without it)
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8

# Install uv (fast Python package manager — matches host preference)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Install ruff (fast Python linter/formatter) — same publisher as uv
COPY --from=ghcr.io/astral-sh/ruff:latest /ruff /usr/local/bin/ruff

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Install git-delta (better diff rendering)
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) \
    && wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
    && dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" \
    && rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Install rtk (CLI proxy for LLM token optimization — needed by pi-rtk-optimizer)
RUN curl -fsSL https://github.com/rtk-ai/rtk/releases/latest/download/rtk-x86_64-unknown-linux-musl.tar.gz \
    | tar xz -C /usr/local/bin rtk

# Install Rust toolchain via rustup (stable, default profile + extras)
# CARGO_HOME/RUSTUP_HOME set before install so rustup uses these paths.
ENV CARGO_HOME=/usr/local/cargo
ENV RUSTUP_HOME=/usr/local/rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile default \
    && "${CARGO_HOME}/bin/rustup" component add rust-analyzer \
    && chmod -R a+rwX "${CARGO_HOME}" "${RUSTUP_HOME}"
ENV PATH="${CARGO_HOME}/bin:${PATH}"

# Install Pi coding agent globally (as root into /usr/local)
RUN npm install -g npm@latest \
    && npm install -g @earendil-works/pi-coding-agent

# Create a non-root user matching the host UID/GID for volume mount permissions.
# Default to 1000:1000; override at build time with --build-arg.
ARG HOST_UID=1000
ARG HOST_GID=1000
RUN groupadd -g ${HOST_GID} agent \
    && useradd -m -u ${HOST_UID} -g ${HOST_GID} -s /bin/bash agent \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent

# Allow the agent user to install global npm packages without sudo.
# npm's default prefix (/usr/local) is root-owned. Redirect global installs
# to ~/.npm-global which the agent user owns, and add it to PATH so Pi can
# find globally installed packages (and its own extensions).
ENV NPM_CONFIG_PREFIX=/home/agent/.npm-global
ENV PATH="/home/agent/.npm-global/bin:${PATH}"
RUN mkdir -p /home/agent/.npm-global /home/agent/.pi/agent \
    && chown -R agent:agent /home/agent/.npm-global /home/agent/.pi

# Switch to non-root user
# WORKDIR is set at runtime via the wrapper script to /home/agent/<project-name>
# so that tools inside the container see the real project directory name.
USER agent
WORKDIR /home/agent

# Default environment
ENV UV_PYTHON_PREFERENCE=system
ENV EDITOR=vim
ENV VISUAL=vim

# Entry point: Pi (permission system runs in yoloMode via config overlay)
# No CMD — when pi-docker passes no args, `pi` starts in interactive mode.
# Args from pi-docker are appended after ENTRYPOINT, overriding any CMD.
ENTRYPOINT ["pi"]
