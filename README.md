# KasmVNC Cinnamon Desktop

A containerized Cinnamon desktop environment accessible via web browser, optimized for HPC/Singularity deployments.

## Features

- Ubuntu 24.04 with Cinnamon desktop
- KasmVNC 1.4.0 web-based remote access
- Nginx reverse proxy with base path support
- UID-aware for Singularity/Apptainer
- Slurm submit host capable
- GPU support (`--nv` flag)
- Adapta-Nokto dark theme

## Quick Start

**Build:**
```bash
./Singularity.sh
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
