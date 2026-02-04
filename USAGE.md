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
- [Troubleshooting](#troubleshooting)
- [File Structure](#file-structure)

## Building

### Singularity/Apptainer (Recommended for HPC)

```bash
# Build as SIF file
./Singularity.sh

# Build as sandbox (no squashfs required)
BUILD_SANDBOX=true ./Singularity.sh
```

### Docker

```bash
docker build -t kasmvnc .
```

## Running

### Basic

```bash
singularity run kasmvnc.sif
```

### Recommended (proper username resolution)

```bash
singularity run \
    --bind /etc/passwd:/etc/passwd:ro \
    --bind /etc/group:/etc/group:ro \
    kasmvnc.sif
```

### Full Featured for HPC

```bash
singularity run \
    --nv \
    --bind /etc/passwd:/etc/passwd:ro \
    --bind /etc/group:/etc/group:ro \
    --bind /scratch \
    --bind /home \
    kasmvnc.sif
```

### Behind Reverse Proxy

```bash
singularity run \
    --nv \
    --env BASE_PATH=/me/session/username/desktop/ \
    --bind /etc/passwd:/etc/passwd:ro \
    --bind /etc/group:/etc/group:ro \
    kasmvnc.sif
```

Access at: `https://<proxy-host>/me/session/username/desktop/`

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NGINX_PORT` | `8080` | External Nginx proxy port |
| `KASM_PORT` | `8590` | Internal KasmVNC websocket port |
| `BASE_PORT` | `8590` | Alias for KASM_PORT (legacy) |
| `BASE_PATH` | `/` | URL base path for reverse proxy |
| `VNC_DISPLAY` | `1` | X display number |
| `CONTAINER_NAME` | `kasmvnc-cinnamon` | Container identifier |

### Examples

```bash
# Custom ports
singularity run --env NGINX_PORT=9000 --env KASM_PORT=9001 kasmvnc.sif

# Direct KasmVNC access (bypass Nginx)
singularity run kasmvnc.sif /usr/local/bin/run_kasm.sh
```

## Included Applications

| Application | Description |
|-------------|-------------|
| Firefox | Web browser |
| Nemo | File manager |
| GNOME Terminal | Terminal emulator |
| gedit | Text editor |
| Evince | PDF viewer |
| Eye of GNOME | Image viewer |
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
    kasmvnc.sif
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
singularity run --nv kasmvnc.sif
```

The container defaults to software rendering (`LIBGL_ALWAYS_SOFTWARE=1`). GPU applications may need to unset this variable.

## Docker Usage

```bash
# Build
docker build -t kasmvnc .

# Run
docker run -p 8080:8080 kasmvnc

# Access at http://localhost:8080/
```

## Enroot Usage

Enroot is NVIDIA's HPC container runtime, optimized for unprivileged container execution, GPU workloads, and Slurm integration via the pyxis plugin.

### Building

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

**Custom image name/tag:**
```bash
IMAGE_NAME=mydesktop IMAGE_TAG=v1.0 ./Enroot.sh
```

| Variable | Default | Description |
|----------|---------|-------------|
| `BUILD_MODE` | auto-detect | `local` (build with Docker) or `registry` (pull from registry) |
| `DOCKER_REGISTRY` | `docker.io/parallelworks/kasmvnc-container` | Registry image path for registry mode |
| `IMAGE_NAME` | `kasmvnc` | Local image name / output prefix |
| `IMAGE_TAG` | `latest` | Image tag |
| `SQSH_FILE` | `${IMAGE_NAME}.sqsh` | Output squashfs filename |

### Running

```bash
# Create container instance
enroot create --name kasmvnc kasmvnc.sqsh

# Basic run
enroot start kasmvnc

# With GPU support
enroot start --env NVIDIA_VISIBLE_DEVICES=all kasmvnc

# With bind mounts and reverse proxy path
enroot start \
    --mount /etc/passwd:/etc/passwd:ro \
    --mount /etc/group:/etc/group:ro \
    --mount /home:/home \
    --env BASE_PATH=/me/session/user/desktop/ \
    --env NGINX_PORT=8080 \
    kasmvnc
```

### Slurm Integration (via pyxis)

```bash
srun --container-image=kasmvnc.sqsh \
     --container-mounts=/etc/passwd:/etc/passwd:ro,/etc/group:/etc/group:ro \
     --container-env=BASE_PATH=/me/session/user/desktop/ \
     /usr/local/bin/run_kasm_nginx.sh
```

### Notes

- Enroot runs as your UID/GID by default (like Singularity)
- Use `--rw` flag if you need a writable container
- For Slurm integration, ensure pyxis plugin is installed
- GPU support requires nvidia-container-cli

## Troubleshooting

### Black screen / Cinnamon not starting

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
singularity run --writable-tmpfs kasmvnc.sif
```

### UID/GID Verification

Singularity runs as your real UID/GID:
```bash
singularity exec kasmvnc.sif id
```

## File Structure

```
.
├── Dockerfile              # Container definition
├── Singularity.sh          # Build script (Singularity/Apptainer)
├── Enroot.sh               # Build script (Enroot)
├── README.md               # Quick start guide
├── USAGE.md                # This file
├── LICENSE                 # MIT License
└── files/
    ├── base_entrypoint.sh  # UID-aware entrypoint
    ├── run_kasm.sh         # KasmVNC startup (direct)
    ├── run_kasm_nginx.sh   # KasmVNC + Nginx startup
    ├── nginx.conf          # Nginx config template
    ├── xstartup            # VNC session startup
    ├── kasmvnc.yaml        # KasmVNC configuration
    ├── sudoers             # Sudo configuration
    └── backgrounds/        # Desktop backgrounds
        └── tealized.jpg    # Default background
```
