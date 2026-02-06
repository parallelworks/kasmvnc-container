# KasmVNC Desktop Usage Guide

## Table of Contents

- [Building](#building)
- [Running](#running)
- [Environment Variables](#environment-variables)
- [Included Applications](#included-applications)
- [Slurm Integration](#slurm-integration)
- [GPU Support](#gpu-support)
- [Docker Usage](#docker-usage)
- [Enroot Usage](#enroot-usage)
- [Proxy-Only Mode](#proxy-only-mode)
- [Troubleshooting](#troubleshooting)
- [File Structure](#file-structure)

## Building

### Singularity/Apptainer (Recommended for HPC)

```bash
# Ubuntu 24.04 - Build as SIF file
./Singularity-ubuntu.sh

# Rocky Linux 9 - Build as SIF file
./Singularity-rocky9.sh

# Build as sandbox (no squashfs required)
BUILD_SANDBOX=true ./Singularity-ubuntu.sh
BUILD_SANDBOX=true ./Singularity-rocky9.sh
```

### Docker

```bash
# Ubuntu 24.04
./Docker-ubuntu.sh
./Docker-ubuntu.sh --push  # Build and push to registry

# Rocky Linux 9
./Docker-rocky9.sh
./Docker-rocky9.sh --push  # Build and push to registry
```

## Running

### Basic

```bash
singularity run kasmvnc-ubuntu.sif
```

### Recommended (proper username resolution)

```bash
singularity run \
    --bind /etc/passwd:/etc/passwd:ro \
    --bind /etc/group:/etc/group:ro \
    kasmvnc-ubuntu.sif
```

### Full Featured for HPC

```bash
singularity run \
    --nv \
    --bind /etc/passwd:/etc/passwd:ro \
    --bind /etc/group:/etc/group:ro \
    --bind /scratch \
    --bind /home \
    kasmvnc-ubuntu.sif
```

### Behind Reverse Proxy

```bash
singularity run \
    --nv \
    --env BASE_PATH=/me/session/username/desktop/ \
    --bind /etc/passwd:/etc/passwd:ro \
    --bind /etc/group:/etc/group:ro \
    kasmvnc-ubuntu.sif
```

Access at: `https://<proxy-host>/me/session/username/desktop/`

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NGINX_PORT` | `8080` | External Nginx proxy port |
| `KASM_PORT` | `8590` | Internal KasmVNC websocket port |
| `BASE_PORT` | `8590` | Alias for KASM_PORT (legacy) |
| `BASE_PATH` | `/` | URL base path for reverse proxy |
| `VNC_DISPLAY` | auto | X display number (auto-detected if not set) |
| `VNC_RESOLUTION` | `1920x1080` | Desktop resolution |
| `CONTAINER_NAME` | `kasmvnc-xfce` | Container identifier |

### Examples

```bash
# Custom ports
singularity run --env NGINX_PORT=9000 --env KASM_PORT=9001 kasmvnc-ubuntu.sif

# Custom resolution
singularity run --env VNC_RESOLUTION=2560x1440 kasmvnc-ubuntu.sif

# Direct KasmVNC access (bypass Nginx)
singularity run kasmvnc-ubuntu.sif /usr/local/bin/run_kasm.sh
```

## Included Applications

| Application | Description |
|-------------|-------------|
| Firefox | Web browser |
| Thunar | File manager |
| XFCE Terminal | Terminal emulator |
| Mousepad | Text editor |
| Evince | PDF viewer |
| Ristretto | Image viewer |
| File Roller | Archive manager |
| htop | System monitor |

## Slurm Integration

The container can act as a Slurm submit host by bind-mounting the cluster's Slurm installation.

### Run Command

```bash
singularity run \
    --bind /etc/passwd:/etc/passwd:ro \
    --bind /etc/group:/etc/group:ro \
    --bind /etc/slurm:/etc/slurm:ro \
    --bind /run/munge:/run/munge \
    --bind /usr/bin/sbatch:/usr/bin/sbatch:ro \
    --bind /usr/bin/srun:/usr/bin/srun:ro \
    --bind /usr/bin/squeue:/usr/bin/squeue:ro \
    --bind /usr/bin/scancel:/usr/bin/scancel:ro \
    --bind /usr/bin/sinfo:/usr/bin/sinfo:ro \
    --bind /usr/bin/sacct:/usr/bin/sacct:ro \
    --bind /usr/bin/salloc:/usr/bin/salloc:ro \
    --bind /usr/lib/x86_64-linux-gnu/slurm:/usr/lib/x86_64-linux-gnu/slurm:ro \
    --bind /scratch \
    --bind /home \
    kasmvnc-ubuntu.sif
```

### Verification

```bash
sinfo          # Show cluster partitions
squeue         # Show job queue
sbatch job.sh  # Submit a job
```

### Notes

- Munge daemon must be running on the host
- Slurm library path may vary (check with `ldd /usr/bin/squeue`)
- Job scripts must be on shared filesystem

## GPU Support

```bash
singularity run --nv kasmvnc-ubuntu.sif
```

The container defaults to software rendering (`LIBGL_ALWAYS_SOFTWARE=1`). GPU applications may need to unset this variable.

## Docker Usage

### Building

```bash
# Build only
./Docker-ubuntu.sh

# Build and push to default registry (parallelworks/kasmvnc)
./Docker-ubuntu.sh --push

# Build and push with specific tag
./Docker-ubuntu.sh --push --tag v1.0.0

# Build and push to custom registry
./Docker-ubuntu.sh --push --registry ghcr.io/myorg/kasmvnc

# Rocky Linux 9
./Docker-rocky9.sh --push
```

| Option | Description |
|--------|-------------|
| `--push` | Push image to registry after building |
| `--tag TAG` | Set image tag (default: latest) |
| `--registry URL` | Set registry path |
| `--no-latest` | Don't push :latest tag (only push specified tag) |

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE_NAME` | `kasmvnc-ubuntu` | Local image name |
| `IMAGE_TAG` | `latest` | Image tag |
| `DOCKER_REGISTRY` | `docker.io/parallelworks/kasmvnc-ubuntu` | Registry path |
| `PUSH` | `false` | Set to `true` to push |
| `PUSH_LATEST` | `true` | Also push :latest when pushing versioned tag |

### Running

```bash
# Run locally
docker run -p 8080:8080 kasmvnc-ubuntu

# Run with custom base path
docker run -p 8080:8080 -e BASE_PATH=/desktop/ kasmvnc-ubuntu

# Access at http://localhost:8080/
```

## Enroot Usage

Enroot is NVIDIA's HPC container runtime, optimized for unprivileged container execution, GPU workloads, and Slurm integration via the pyxis plugin.

### Building / Installing

The build script supports two modes and auto-detects which to use based on Docker availability:

**Local mode** (requires Docker):
```bash
# Build Docker image locally and convert to Enroot squashfs
./Enroot.sh

# Or explicitly force local mode
BUILD_MODE=local ./Enroot.sh
```

**Registry mode** (no Docker required):
```bash
# Pull pre-built image directly from Docker registry
BUILD_MODE=registry ./Enroot.sh

# Or from a custom registry
DOCKER_REGISTRY=myregistry.io/myorg/kasmvnc ./Enroot.sh
```

### Shared Installation for HPC Clusters

Install containers to a shared location accessible by all users:

```bash
# Set shared path (adjust to your environment)
SHARED_PATH=/shared/containers

# Import Ubuntu 24.04 container
enroot import -o ${SHARED_PATH}/kasmvnc-ubuntu.sqsh docker://parallelworks/kasmvnc-ubuntu:latest

# Import Rocky Linux 9 container
enroot import -o ${SHARED_PATH}/kasmvnc-rocky9.sqsh docker://parallelworks/kasmvnc-rocky9:latest

# Import lightweight proxy container
enroot import -o ${SHARED_PATH}/kasmproxy.sqsh docker://parallelworks/kasmproxy:latest
```

**Important:** For Docker Hub images, use `docker://parallelworks/...` format (without `docker.io/` prefix).

| Variable | Default | Description |
|----------|---------|-------------|
| `BUILD_MODE` | auto-detect | `local` (build with Docker) or `registry` (pull from registry) |
| `DOCKER_REGISTRY` | `parallelworks/kasmvnc-ubuntu` | Registry image path (no `docker.io/` for Docker Hub) |
| `IMAGE_NAME` | `kasmvnc` | Local image name / output prefix |
| `IMAGE_TAG` | `latest` | Image tag |
| `SQSH_FILE` | `${IMAGE_NAME}.sqsh` | Output squashfs filename |

### Running

```bash
# Create container instance from shared squashfs
enroot create --name kasmvnc-ubuntu /shared/containers/kasmvnc-ubuntu.sqsh

# Basic run
enroot start kasmvnc-ubuntu

# With GPU support
enroot start --env NVIDIA_VISIBLE_DEVICES=all kasmvnc-ubuntu

# With bind mounts and reverse proxy path
enroot start \
    --mount /etc/passwd:/etc/passwd:ro \
    --mount /etc/group:/etc/group:ro \
    --mount /home:/home \
    --env BASE_PATH=/me/session/$USER/desktop/ \
    --env NGINX_PORT=8080 \
    kasmvnc-ubuntu
```

### User Instructions (for shared installations)

Share these instructions with users:

```bash
# Create your container instance (one-time setup)
enroot create --name kasmvnc-ubuntu /shared/containers/kasmvnc-ubuntu.sqsh

# Run the desktop
enroot start \
    --mount /etc/passwd:/etc/passwd:ro \
    --mount /etc/group:/etc/group:ro \
    --mount /home:/home \
    --env BASE_PATH=/me/session/$USER/desktop/ \
    kasmvnc

# For Rocky Linux 9 version:
enroot create --name kasmvnc-rocky9 /shared/containers/kasmvnc-rocky9.sqsh
enroot start \
    --mount /etc/passwd:/etc/passwd:ro \
    --mount /etc/group:/etc/group:ro \
    --mount /home:/home \
    --env BASE_PATH=/me/session/$USER/desktop/ \
    kasmvnc-rocky9
```

### Slurm Integration (via pyxis)

```bash
srun --container-image=/shared/containers/kasmvnc-ubuntu.sqsh \
     --container-mounts=/etc/passwd:/etc/passwd:ro,/etc/group:/etc/group:ro \
     --container-env=BASE_PATH=/me/session/$USER/desktop/ \
     /usr/local/bin/run_kasm_nginx.sh
```

### Notes

- Enroot runs as your UID/GID by default (like Singularity)
- Use `--rw` flag if you need a writable container
- For Slurm integration, ensure pyxis plugin is installed
- GPU support requires nvidia-container-cli
- If FUSE is unavailable, you must run `enroot create` before `enroot start`

## Proxy-Only Mode

Use a lightweight Nginx proxy when KasmVNC is already running on the host.

### Lightweight Proxy Container

A minimal container (~100MB) with just Nginx - no desktop environment.

**Building:**
```bash
./Docker-proxy.sh              # Docker - Build only
./Docker-proxy.sh --push       # Docker - Build and push to registry
./Singularity-proxy.sh         # Singularity - Build SIF file
```

**Running (Singularity):**
```bash
singularity run \
    --env KASM_HOST=<host-ip> \
    --env KASM_PORT=8443 \
    --env NGINX_PORT=8080 \
    --env BASE_PATH=/me/session/user/desktop/ \
    kasmproxy.sif
```

**Running (Docker):**
```bash
docker run -p 8080:8080 \
    -e KASM_HOST=<host-ip> \
    -e KASM_PORT=8443 \
    -e BASE_PATH=/me/session/user/desktop/ \
    kasmproxy
```

**Running (Enroot):**
```bash
enroot import -o kasmproxy.sqsh docker://parallelworks/kasmproxy:latest
enroot create --name kasmproxy kasmproxy.sqsh
enroot start \
    -e KASM_HOST=<host-ip> \
    -e KASM_PORT=8443 \
    -e BASE_PATH=/me/session/user/desktop/ \
    kasmproxy
```

### Using Full Container as Proxy

Alternatively, use the full container as a lightweight Nginx proxy when KasmVNC is already running on the host.

### When to Use

- KasmVNC is installed directly on the host system
- You only need BASE_PATH routing for reverse proxy integration
- Lighter footprint than full desktop container

### Running

```bash
# Basic - proxy to KasmVNC on localhost:8443
singularity run kasmvnc-ubuntu.sif /usr/local/bin/run_nginx_proxy.sh

# With custom KasmVNC port
singularity run --env KASM_PORT=6901 kasmvnc-ubuntu.sif /usr/local/bin/run_nginx_proxy.sh

# With BASE_PATH for reverse proxy
singularity run \
    --env KASM_PORT=8443 \
    --env BASE_PATH=/me/session/user/desktop/ \
    --env NGINX_PORT=8080 \
    kasmvnc-ubuntu-ubuntu.sif /usr/local/bin/run_nginx_proxy.sh

# Connect to KasmVNC on different host
singularity run \
    --env KASM_HOST=192.168.1.100 \
    --env KASM_PORT=8443 \
    kasmvnc-ubuntu.sif /usr/local/bin/run_nginx_proxy.sh
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `KASM_HOST` | `127.0.0.1` | Host where KasmVNC is running |
| `KASM_PORT` | `8443` | KasmVNC websocket port |
| `NGINX_PORT` | `8080` | Nginx listen port |
| `BASE_PATH` | `/` | URL base path for routing |

## Troubleshooting

### Black screen / XFCE not starting

Check VNC log:
```bash
cat ~/.vnc/*.log
```

### Connection refused on port 8080

Verify services are running:
```bash
ps aux | grep -E "(Xvnc|nginx)"
```

### "I have no name!" in terminal

Bind-mount passwd files:
```bash
--bind /etc/passwd:/etc/passwd:ro --bind /etc/group:/etc/group:ro
```

### Permission denied errors

Use writable tmpfs overlay:
```bash
singularity run --writable-tmpfs kasmvnc-ubuntu.sif
```

### UID/GID Verification

Singularity runs as your real UID/GID:
```bash
singularity exec kasmvnc-ubuntu.sif id
```

### Enroot "Could not process JSON input" error

Use the correct Docker Hub URL format (without `docker.io/`):
```bash
# Correct
enroot import -o kasmvnc-ubuntu.sqsh docker://parallelworks/kasmvnc-ubuntu:latest

# Incorrect - may cause errors
enroot import -o kasmvnc.sqsh docker://docker.io/parallelworks/kasmvnc:latest
```

## File Structure

```
.
├── Dockerfile.ubuntu       # Full desktop container (Ubuntu 24.04)
├── Dockerfile.rocky9       # Full desktop container (Rocky Linux 9)
├── Dockerfile.proxy        # Lightweight proxy-only container
├── Docker-ubuntu.sh        # Build script (Ubuntu container)
├── Docker-rocky9.sh        # Build script (Rocky 9 container)
├── Docker-proxy.sh         # Build script (proxy container)
├── Singularity-ubuntu.sh   # Build script (Singularity Ubuntu)
├── Singularity-rocky9.sh   # Build script (Singularity Rocky 9)
├── Singularity-proxy.sh    # Build script (Singularity proxy)
├── Enroot.sh               # Build script (Enroot)
├── README.md               # Quick start guide
├── USAGE.md                # This file
├── LICENSE                 # MIT License
└── files/
    ├── base_entrypoint.sh  # UID-aware entrypoint
    ├── run_kasm.sh         # KasmVNC startup (direct)
    ├── run_kasm_nginx.sh   # KasmVNC + Nginx startup
    ├── run_nginx_proxy.sh  # Nginx proxy only (for host KasmVNC)
    ├── nginx.conf          # Nginx config template
    ├── xstartup            # VNC session startup
    ├── kasmvnc.yaml        # KasmVNC configuration
    ├── sudoers             # Sudo configuration
    └── backgrounds/        # Desktop backgrounds
        └── tealized.jpg    # Default background
```
