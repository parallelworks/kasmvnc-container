#!/bin/bash
#
# Build a Singularity container from the Dockerfile
#
# HPC Considerations:
# - Build on a system where you have root/Docker access, then transfer the .sif
# - SIF files are portable and don't require root to RUN (only to BUILD)
# - Use --sandbox format if squashfs is unavailable on target system
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
IMAGE_NAME="${IMAGE_NAME:-kasmvnc}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
SIF_FILE="${SIF_FILE:-${IMAGE_NAME}.sif}"
BUILD_SANDBOX="${BUILD_SANDBOX:-false}"  # Set to 'true' for directory format

echo "=== Building Singularity container from Dockerfile ==="
echo "Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""

# Step 1: Build Docker image
echo "Step 1: Building Docker image..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" "${SCRIPT_DIR}"

# Step 2: Convert to Singularity
echo ""
echo "Step 2: Converting Docker image to Singularity..."

if [ "${BUILD_SANDBOX}" = "true" ]; then
    # Sandbox format - directory-based, no squashfs needed on target
    SANDBOX_DIR="${IMAGE_NAME}_sandbox"
    echo "Building as sandbox directory: ${SANDBOX_DIR}"

    if [ -d "${SANDBOX_DIR}" ]; then
        echo "Removing existing ${SANDBOX_DIR}..."
        rm -rf "${SANDBOX_DIR}"
    fi

    singularity build --sandbox "${SANDBOX_DIR}" "docker-daemon://${IMAGE_NAME}:${IMAGE_TAG}"

    echo ""
    echo "=== Build complete (sandbox) ==="
    echo "Singularity sandbox: ${SANDBOX_DIR}/"
    echo ""
    echo "To run on HPC:"
    echo "  singularity run ${SANDBOX_DIR}"
    echo "  singularity exec ${SANDBOX_DIR} <command>"
    echo ""
    echo "To convert sandbox to SIF later (requires squashfs):"
    echo "  singularity build ${SIF_FILE} ${SANDBOX_DIR}/"
else
    # SIF format - single file, requires squashfs support on target
    echo "Building as SIF file: ${SIF_FILE}"

    if [ -f "${SIF_FILE}" ]; then
        echo "Removing existing ${SIF_FILE}..."
        rm -f "${SIF_FILE}"
    fi

    singularity build "${SIF_FILE}" "docker-daemon://${IMAGE_NAME}:${IMAGE_TAG}"

    echo ""
    echo "=== Build complete (SIF) ==="
    echo "Singularity container: ${SIF_FILE}"
fi

CONTAINER="${SIF_FILE:-${IMAGE_NAME}_sandbox}"

echo ""
echo "=== HPC Runtime Examples ==="
echo ""
echo "# Basic run (UID/GID automatically maps to your user):"
echo "  singularity run ${CONTAINER}"
echo ""
echo "# RECOMMENDED: With proper username resolution (whoami shows your real name):"
echo "  singularity run --bind /etc/passwd:/etc/passwd:ro --bind /etc/group:/etc/group:ro ${CONTAINER}"
echo ""
echo "# With common HPC bind mounts:"
echo "  singularity run --bind /etc/passwd:/etc/passwd:ro,/etc/group:/etc/group:ro,/scratch,/home ${CONTAINER}"
echo ""
echo "# With writable temp overlay (for apps that write to container paths):"
echo "  singularity run --writable-tmpfs ${CONTAINER}"
echo ""
echo "# With GPU support (if NVIDIA drivers available):"
echo "  singularity run --nv ${CONTAINER}"
echo ""
echo "# Full featured (recommended for HPC):"
echo "  singularity run --nv --bind /etc/passwd:/etc/passwd:ro,/etc/group:/etc/group:ro,/scratch,/home ${CONTAINER}"
echo ""
echo "# As Slurm submit host (bind-mount cluster's Slurm installation):"
cat << 'SLURM_EOF'
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
SLURM_EOF
echo ""
echo "=== Notes ==="
echo "- Singularity automatically runs as YOUR UID/GID (verify with 'id' command inside)"
echo "- Bind-mounting /etc/passwd makes 'whoami' show your real username"
echo "- The container uses NGINX_PORT=8080 by default, set env var to change"
echo "- Access the desktop at: http://<hostname>:8080/"
echo "- For Slurm: library path may vary, check with 'ldd /usr/bin/squeue' on host"
