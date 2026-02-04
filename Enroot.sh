#!/bin/bash
#
# Build an Enroot container from the Dockerfile
#
# Enroot is NVIDIA's HPC container runtime, optimized for:
# - Unprivileged container execution
# - GPU workloads with native NVIDIA support
# - Slurm integration via pyxis plugin
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
IMAGE_NAME="${IMAGE_NAME:-kasmvnc}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
SQSH_FILE="${SQSH_FILE:-${IMAGE_NAME}.sqsh}"

echo "=== Building Enroot container from Dockerfile ==="
echo "Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""

# Step 1: Build Docker image
echo "Step 1: Building Docker image..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" "${SCRIPT_DIR}"

# Step 2: Convert to Enroot squashfs
echo ""
echo "Step 2: Converting Docker image to Enroot squashfs..."

if [ -f "${SQSH_FILE}" ]; then
    echo "Removing existing ${SQSH_FILE}..."
    rm -f "${SQSH_FILE}"
fi

# Import from Docker daemon
enroot import -o "${SQSH_FILE}" "dockerd://${IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo "=== Build complete ==="
echo "Enroot container: ${SQSH_FILE}"
echo ""
echo "=== Enroot Runtime Examples ==="
echo ""
echo "# Create container instance:"
echo "  enroot create --name ${IMAGE_NAME} ${SQSH_FILE}"
echo ""
echo "# Basic run:"
echo "  enroot start ${IMAGE_NAME}"
echo ""
echo "# With GPU support:"
echo "  enroot start --env NVIDIA_VISIBLE_DEVICES=all ${IMAGE_NAME}"
echo ""
echo "# With bind mounts and custom BASE_PATH:"
echo "  enroot start \\"
echo "      --mount /etc/passwd:/etc/passwd:ro \\"
echo "      --mount /etc/group:/etc/group:ro \\"
echo "      --mount /home:/home \\"
echo "      --env BASE_PATH=/me/session/user/desktop/ \\"
echo "      --env NGINX_PORT=8080 \\"
echo "      ${IMAGE_NAME}"
echo ""
echo "# With Slurm (via pyxis plugin):"
echo "  srun --container-image=${SQSH_FILE} \\"
echo "       --container-mounts=/etc/passwd:/etc/passwd:ro,/etc/group:/etc/group:ro \\"
echo "       --container-env=BASE_PATH=/me/session/user/desktop/ \\"
echo "       /usr/local/bin/run_kasm_nginx.sh"
echo ""
echo "=== Notes ==="
echo "- Enroot runs as your UID/GID by default (like Singularity)"
echo "- Use --rw flag if you need a writable container"
echo "- For Slurm integration, ensure pyxis plugin is installed"
echo "- GPU support requires nvidia-container-cli"
