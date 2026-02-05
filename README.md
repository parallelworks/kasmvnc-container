# KasmVNC XFCE Desktop

A containerized XFCE desktop environment accessible via web browser, optimized for HPC/Singularity deployments.

## Features

- Ubuntu 24.04 with XFCE desktop (lightweight, works without system D-Bus)
- KasmVNC 1.4.0 web-based remote access
- Nginx reverse proxy with BASE_PATH support
- UID-aware for Singularity/Apptainer/Enroot
- HPC software dependencies (csh, ksh, 32-bit libs)
- Slurm submit host capable
- GPU support (`--nv` flag)
- Adapta-Nokto dark theme

## Containers

| Container | Description | Size |
|-----------|-------------|------|
| `kasmvnc` | Full desktop environment | ~2GB |
| `kasmproxy` | Lightweight nginx proxy only | ~25MB |

## Quick Start

**Build (Docker):**
```bash
./Docker.sh

# Build and push to registry
./Docker.sh --push
```

**Build (Singularity/Apptainer):**
```bash
./Singularity.sh
```

**Build (Enroot):**
```bash
./Enroot.sh
```

**Build Proxy Only (lightweight):**
```bash
./Docker-proxy.sh --push       # Docker
./Singularity-proxy.sh         # Singularity
```

**Run (basic):**
```bash
singularity run \
    --bind /etc/passwd:/etc/passwd:ro \
    --bind /etc/group:/etc/group:ro \
    kasmvnc.sif
```

**Run (with GPU and reverse proxy path):**
```bash
singularity run \
    --nv \
    --env BASE_PATH=/me/session/username/desktop/ \
    --bind /etc/passwd:/etc/passwd:ro \
    --bind /etc/group:/etc/group:ro \
    kasmvnc.sif
```

**Run Proxy Only (when KasmVNC is on host):**
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
- Slurm integration
- GPU support
- Troubleshooting

## License

MIT License - See [LICENSE](LICENSE) for details.
