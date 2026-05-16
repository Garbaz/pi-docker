# Pi Docker Isolation

Run the Pi coding agent in an isolated Docker container with persistent config and project workspaces.

## Quick Start

```bash
# 1. Build the base image (one-time, or after changing Dockerfile)
pi-docker --build

# 2. Run Pi in the current directory (always YOLO — container is the boundary)
pi-docker

# 3. Drop into a shell inside the container
pi-docker --shell
```

## Architecture

```
~/.pi/docker/
├── Dockerfile                    # Base Pi image (Node 22, Python 3, uv, git, gh, pi)
├── pi-docker                     # Wrapper script (build, run, extend, clean)
├── permission-config.json        # YOLO mode config overlay for the container
├── .dockerignore                 # Keep build context lean
├── Dockerfile.extend.template    # Template for per-project image extensions
└── README.md                     # This file

Per-project (in project root):
└── Dockerfile.extend             # Project-specific packages (FROM pi-base:latest)
```

## How It Works

### Base Image (`pi-base:latest`)

Built from `~/.pi/docker/Dockerfile`. Contains:
- Node.js 22 (via official slim image)
- Python 3 + uv
- Git, GitHub CLI, curl, jq, ripgrep, fd-find
- Pi coding agent (installed globally via npm)
- Non-root user matching host UID/GID (for volume mount permissions)

### Layering Strategy

Docker image inheritance through `FROM`:

1. **Base image** (`pi-base:latest`): Built once from `~/.pi/docker/Dockerfile`. Has everything Pi needs to run.

2. **Project image** (`pi-<project>:latest`): Built from a project's `Dockerfile.extend`, which starts with `FROM pi-base:latest` and adds project-specific deps (libpq-dev, numpy, etc.). Docker reuses unchanged layers from the base.

### Volume Mounts

| Host path | Container path | Mode | Purpose |
|-----------|---------------|------|---------|
| `~/.pi/agent` | `/home/agent/.pi/agent` | rw | Pi config, settings, auth |
| `~/.pi/docker/permission-config.json` | `.../pi-permission-system/config.json` | ro | YOLO mode overlay (auto-approves all permissions) |
| `<project>/` | `/home/agent/<dirname>` | rw | Project source code (preserves real dir name) |
| `~/.gitconfig` | `/home/agent/.gitconfig` | ro | Git identity for commits |
| `~/.ssh/known_hosts` | `/home/agent/.ssh/known_hosts` | ro | SSH host verification |

### GPU Passthrough

All available NVIDIA GPUs are passed through via `--gpus all`. Requires the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/installation-guide.html) on the host.

### Security

- Container runs as non-root user (`agent`)
- No resource limits by default — containers get full access to host CPU, memory, and GPU
- YOLO mode is always on — the container IS the security boundary, Pi can't touch your host filesystem outside the mounted volumes
- `.gitconfig` and `known_hosts` are read-only — Pi can read your git identity but can't alter it
- Permission system config is overlaid with `yoloMode: true` — all `ask` prompts are auto-approved inside the container

## Project Extensions

```bash
# 1. Create Dockerfile.extend in project root
cp ~/.pi/docker/Dockerfile.extend.template ./Dockerfile.extend

# 2. Edit it — add what you need
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

## CLI Reference

```
pi-docker [OPTIONS] [PI_ARGS...]

Options:
  --project DIR    Use DIR as workspace (default: current directory)
  --build          Build or rebuild the base Pi Docker image
  --extend         Build the project-extended image (requires Dockerfile.extend)
  --shell          Drop into a bash shell inside the container
  --stop           Stop the running container for this project
  --clean          Remove containers and project-specific image
  --help           Show this help message
```

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | Passed through to container |
| `OPENAI_API_KEY` | Passed through to container |
| `OPENROUTER_API_KEY` | Passed through to container |
| `GITHUB_TOKEN` | Passed through to container |
| `PI_IN_DOCKER` | Set to `1` inside the container (can be used for detection) |

## Tips

- **Multiple projects**: Each project gets its own container name (`pi-<slug>`), so you can run Pi in multiple projects simultaneously.
- **SSH agent forwarding**: If you need git push access, add `-v $SSH_AUTH_SOCK:/ssh-agent -e SSH_AUTH_SOCK=/ssh-agent` or mount your SSH key.
- **Rebuilding after Pi updates**: Run `pi-docker --build` to pick up the latest Pi version.
