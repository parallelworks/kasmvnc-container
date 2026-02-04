# KasmVNC Desktop Usage Guide

## Table of Contents

- [Building](#building)
- [Running](#running)
- [Environment Variables](#environment-variables)
- [Included Applications](#included-applications)
- [Slurm Integration](#slurm-integration)
- [GPU Support](#gpu-support)
- [Docker Usage](#docker-usage)
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
├── Singularity.sh          # Build script
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
    └── sudoers             # Sudo configuration
```
