# KasmVNC XFCE Desktop

A containerized XFCE desktop environment accessible via web browser, optimized for HPC/Singularity deployments.

## Features

- **Two OS options:** Ubuntu 24.04 or Rocky Linux 9
- XFCE desktop (lightweight, works without system D-Bus)
- KasmVNC 1.4.0 web-based remote access
- Nginx reverse proxy with BASE_PATH support
- UID-aware for Singularity/Apptainer/Enroot
- HPC software dependencies (csh, ksh, gdb, 32-bit libs)
- Slurm submit host capable
- GPU support (`--nv` flag)
- Adwaita-dark theme with dark green background

## Containers

| Container | Base OS | Description | Registry |
|-----------|---------|-------------|----------|
| `kasmvnc-ubuntu` | Ubuntu 24.04 | Full desktop environment | `parallelworks/kasmvnc-ubuntu` |
| `kasmvnc-rocky9` | Rocky Linux 9 | Full desktop environment | `parallelworks/kasmvnc-rocky9` |
| `kasmproxy` | Ubuntu 24.04 | Lightweight nginx proxy only | `parallelworks/kasmproxy` |

## Quick Start

### Build (Docker)

```bash
# Ubuntu 24.04
./Docker-ubuntu.sh --push

# Rocky Linux 9
./Docker-rocky9.sh --push
```

### Build (Singularity/Apptainer)

```bash
# Ubuntu 24.04
./Singularity-ubuntu.sh

# Rocky Linux 9
./Singularity-rocky9.sh
```

### Build (Enroot)

```bash
# Local build (requires Docker)
./Enroot.sh

# Pull from registry to shared location (no Docker required)
enroot import -o /shared/containers/kasmvnc-ubuntu.sqsh docker://parallelworks/kasmvnc-ubuntu:latest
enroot import -o /shared/containers/kasmvnc-rocky9.sqsh docker://parallelworks/kasmvnc-rocky9:latest
```

### Build Proxy Only (lightweight)

```bash
./Docker-proxy.sh --push       # Docker
./Singularity-proxy.sh         # Singularity
```

### Run (Singularity)

```bash
singularity run \
    --bind /etc/passwd:/etc/passwd:ro \
    --bind /etc/group:/etc/group:ro \
    kasmvnc-ubuntu.sif
```

### Run (with GPU and reverse proxy path)

```bash
singularity run \
    --nv \
    --env BASE_PATH=/me/session/username/desktop/ \
    --bind /etc/passwd:/etc/passwd:ro \
    --bind /etc/group:/etc/group:ro \
    kasmvnc-ubuntu.sif
```

### Run (Enroot from shared location)

```bash
# Create instance from shared squashfs
enroot create --name kasmvnc-ubuntu /shared/containers/kasmvnc-ubuntu.sqsh

# Run
enroot start \
    --mount /etc/passwd:/etc/passwd:ro \
    --mount /etc/group:/etc/group:ro \
    --env BASE_PATH=/me/session/$USER/desktop/ \
    kasmvnc-ubuntu
```

### Run Proxy Only (when KasmVNC is on host)

```bash
docker run -p 8080:8080 \
    -e KASM_HOST=<host-ip> \
    -e KASM_PORT=8443 \
    -e BASE_PATH=/me/session/user/desktop/ \
    kasmproxy
```

**Access:** Open `http://<hostname>:8080/` (or your configured `BASE_PATH`) in your browser.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NGINX_PORT` | `8080` | External web port |
| `KASM_PORT` | `8590` | Internal VNC port |
| `BASE_PATH` | `/` | URL base path |

## Documentation

See [USAGE.md](USAGE.md) for detailed documentation including:
- Advanced configuration
- Shared installation for HPC clusters
- Slurm integration
- GPU support
- Troubleshooting

## License

MIT License - See [LICENSE](LICENSE) for details.
