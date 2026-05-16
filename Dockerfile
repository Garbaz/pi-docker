# =============================================================================
# Pi Coding Agent — Base Docker Image
# =============================================================================
# This is the base image for running Pi in an isolated container.
# Projects can extend this by creating a Dockerfile.extend in their project root
# that starts with:  FROM pi-base:latest
#
# Build:  docker build -t pi-base:latest /home/tobi/.pi/docker
# =============================================================================

FROM node:22-slim AS base

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

# Install Pi coding agent globally
RUN npm install -g @earendil-works/pi-coding-agent

# Create a non-root user matching the host UID/GID for volume mount permissions.
# Default to 1000:1000; override at build time with --build-arg.
ARG HOST_UID=1000
ARG HOST_GID=1000
RUN groupadd -g ${HOST_GID} agent \
    && useradd -m -u ${HOST_UID} -g ${HOST_GID} -s /bin/bash agent

# Create config directory (workspace dir is created at runtime by the wrapper)
RUN mkdir -p /home/agent/.pi/agent \
    && chown -R agent:agent /home/agent/.pi

# Switch to non-root user
# WORKDIR is set at runtime via the wrapper script to /home/agent/<project-name>
# so that tools inside the container see the real project directory name.
USER agent
WORKDIR /home/agent

# Default environment: use uv for Python
ENV UV_PYTHON_PREFERENCE=system

# Entry point: Pi in YOLO mode (safe because the container IS the security boundary)
ENTRYPOINT ["pi"]
CMD ["--help"]
