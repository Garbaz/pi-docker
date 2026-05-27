# pi-docker

Run the [Pi coding agent](https://github.com/earendil-works/pi-coding-agent) in an isolated Docker container with persistent config, GPU passthrough, and YOLO mode — the container IS the security boundary.

## Features

- **One command to run**: `pi-docker` builds the image, mounts your project, and starts Pi
- **YOLO by default**: Permission system runs in `yoloMode` inside the container — no prompts
- **GPU passthrough**: Opt-in with `--gpus` flag (requires [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/installation-guide.html))
- **Persistent config**: `~/.pi/agent` is mounted read-write — settings, auth, and sessions persist
- **Cached extensions**: `~/.pi/docker/npm-global` persists npm packages across runs — fast startup
- **Project-aware workspace**: Mounts at `/home/agent/<dirname>` so tools see the real project name
- **Per-project extensions**: Add project-specific deps via `Dockerfile.extend` (inherits from base)
- **Auto-mount paths**: File paths in forwarded arguments (e.g. `--extension /path/to/ext`) are auto-detected and mounted into the container
- **Non-root container**: Matches your host UID/GID so volume mounts work correctly

## Requirements

- [Docker Engine](https://docs.docker.com/engine/install/) 20.10+ (with `docker run` support)
- Bash (for the wrapper script)

## Install

```bash
# Clone the repo
git clone git@github.com:Garbaz/pi-docker.git ~/.pi/docker

# Add the wrapper script to your PATH
ln -s ~/.pi/docker/pi-docker ~/.local/bin/pi-docker
```

Or add `~/.pi/docker` to your `PATH` directly:

```bash
export PATH="$HOME/.pi/docker:$PATH"
```

## Quick Start

```bash
# 1. Build the base image and run Pi
pi-docker --build

# Or: clean rebuild from scratch (no Docker cache) then run
pi-docker --rebuild

# Just build without running (e.g. for CI)
pi-docker --build-only

# Run Pi in the current directory (after initial build)
pi-docker
```

Pi runs in YOLO mode inside the container — all permission prompts are auto-approved. The container boundary prevents access to anything outside the mounted volumes.

## CLI

```
pi-docker [OPTIONS] [PI_ARGS...]

Options:
  --project DIR    Use DIR as workspace (default: current directory)
  --attach         Attach to a running container for this project
  --gpus           Pass all NVIDIA GPUs to the container
  --build          Build or rebuild the base Pi Docker image
  --extend         Build project-extended image (requires Dockerfile.extend)
  --shell          Drop into a bash shell inside the container
  --stop           Stop all running containers for this project
  --clean          Remove containers and project-specific image
  --help           Show this help message

Any additional arguments are passed to Pi.

### Auto-Mounting Extra Paths

When `pi-docker` forwards arguments to `pi`, it automatically detects file and directory paths and mounts them into the container. This means you can reference extensions, skills, themes, or any local files — even if they're outside the project workspace — and they'll just work.

**Detected patterns:**
- Flag-value pairs: `--extension /path/to/ext.js`, `--skill ~/my-skill/`, `--session /tmp/debug.json`
- `@file` references: `pi-docker @~/docs/instructions.md "What does this say?"`
- Standalone paths: `pi-docker /some/script.py "Explain this"`

**Mount scheme:** Each detected path is mounted at `/mnt/pi-args/<n>/<basename>` inside the container, and the argument is rewritten to point to that container path. This works even for paths inside the project workspace — Docker handles overlapping mounts gracefully. Duplicate paths reuse the same mount.

```bash
# Load an extension from outside the workspace — auto-mounted
pi-docker --extension ~/dev/pi-plugins/my-ext.ts

# Reference a prompt file anywhere on disk
pi-docker @~/notes/task.md "Implement this"

# Use a custom theme directory
pi-docker --theme ~/dev/pi-themes/dracula
```

> **Note:** Auto-mounts only work when starting a new container (`pi-docker` or `pi-docker --attach` with no extra paths). `--attach` to a running container errors if extra paths are detected, since mounts can't be added to a running container.

## How It Works

### Base Image (`pi-base:latest`)

Built from the `Dockerfile`. Contains:
- Node.js 22 (official slim image) + npm (latest)
- Python 3 + pip + [uv](https://docs.astral.sh/uv/) + [ruff](https://docs.astral.sh/ruff/)
- Rust toolchain (rustup stable, minimal profile)
- Git, GitHub CLI (`gh`), git-delta
- curl, wget, jq, ripgrep, fd (symlinked from `fd-find`), vim, nano, less, procps
- SSH client, sudo (passwordless for agent user), patch, file, pkg-config
- rtk (LLM token optimizer)
- Pi coding agent (installed globally via npm)
- Non-root user `agent` matching your host UID/GID
- UTF-8 locale, `EDITOR=vim`

### Volume Mounts

| Host path | Container path | Mode | Purpose |
|-----------|---------------|------|---------|
| `~/.pi/agent` | `/home/agent/.pi/agent` | rw | Pi config, settings, auth |
| `~/.pi/docker/permission-config.json` | `.../pi-permission-system/config.json` | ro | YOLO mode overlay |
| `~/.pi/docker/npm-global` | `/home/agent/.npm-global` | rw | Cached npm packages (fast startup) |
| `<project>/` | `/home/agent/<dirname>` | rw | Project source code |
| `<extra paths>` | `/mnt/pi-args/<n>/<name>` | rw | Auto-mounted from forwarded args |
| `~/.gitconfig` | `/home/agent/.gitconfig` | ro | Git identity (if exists) |
| `~/.ssh/known_hosts` | `/home/agent/.ssh/known_hosts` | ro | SSH host verification (if exists) |

### YOLO Mode

A minimal `permission-config.json` with `{ "yoloMode": true }` is mounted over the permission system's config file. This auto-approves all `ask` prompts inside the container. Your host config is untouched.

### Security Model

- The container IS the security boundary — Pi can only access the mounted volumes
- `.gitconfig` and `.ssh/known_hosts` are mounted read-only
- Container runs as non-root user `agent`
- No resource limits — containers get full access to host CPU and memory

## Project Extensions

Add project-specific dependencies by creating a `Dockerfile.extend` in your project root:

```bash
# 1. Copy the template
cp ~/.pi/docker/Dockerfile.extend.template ./Dockerfile.extend

# 2. Edit it — add whatever you need
#    FROM pi-base:latest
#    USER root
#    RUN apt-get update && apt-get install -y libpq-dev
#    RUN uv pip install --system numpy pandas httpx
#    USER agent

# 3. Build the extended image
pi-docker --extend

# 4. Run — the extended image is used automatically
pi-docker
```

Extended images inherit all layers from `pi-base:latest` — only the new layers are rebuilt.

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | Passed through to container |
| `OPENAI_API_KEY` | Passed through to container |
| `OPENROUTER_API_KEY` | Passed through to container |
| `GITHUB_TOKEN` | Passed through to container |
| `PI_IN_DOCKER` | Set to `1` inside the container |

## Tips

- **Multiple projects**: Each invocation gets a unique container name (`pi-<slug>-xxxx`), so you can run Pi in multiple projects simultaneously
- **Attach to a running container**: Use `pi-docker --attach` to join an already running Pi session in the same project
- **GPU access**: Pass `--gpus` to enable NVIDIA GPU passthrough (requires [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/installation-guide.html))
- **SSH agent forwarding**: If you need git push access, mount your SSH agent: add `-v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent`
- **Rebuilding after Pi updates**: Run `pi-docker --build` to pick up the latest Pi version
- **Custom API keys**: Set them in your shell before running: `OPENAI_API_KEY=sk-... pi-docker`
- **Stale image warning**: If the Dockerfile changed since your last build, `pi-docker` will warn you to run `--build`

## File Structure

```
~/.pi/docker/
├── Dockerfile                    # Base Pi image
├── pi-docker                     # Wrapper script
├── permission-config.json        # YOLO mode config overlay
├── npm-global/                   # Cached npm packages (persisted across runs)
├── .dockerignore                 # Keep build context lean
├── Dockerfile.extend.template    # Template for per-project extensions
└── README.md                     # This file

Per-project (in project root):
└── Dockerfile.extend             # Project-specific packages (FROM pi-base:latest)
```
