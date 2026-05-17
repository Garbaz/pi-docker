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
    && rm -rf /var/lib/apt/lists/*

# Install uv (fast Python package manager — matches host preference)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Install rtk (CLI proxy for LLM token optimization — needed by pi-rtk-optimizer)
RUN curl -fsSL https://github.com/rtk-ai/rtk/releases/latest/download/rtk-x86_64-unknown-linux-musl.tar.gz \
    | tar xz -C /usr/local/bin rtk

# Install Rust toolchain via rustup (stable, minimal profile)
# CARGO_HOME/RUSTUP_HOME set before install so rustup uses these paths.
ENV CARGO_HOME=/usr/local/cargo
ENV RUSTUP_HOME=/usr/local/rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile minimal \
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
    && useradd -m -u ${HOST_UID} -g ${HOST_GID} -s /bin/bash agent

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

# Default environment: use uv for Python
ENV UV_PYTHON_PREFERENCE=system

# Entry point: Pi (permission system runs in yoloMode via config overlay)
# No CMD — when pi-docker passes no args, `pi` starts in interactive mode.
# Args from pi-docker are appended after ENTRYPOINT, overriding any CMD.
ENTRYPOINT ["pi"]
