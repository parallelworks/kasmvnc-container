#!/bin/bash
#
# Build an Enroot container from Dockerfile or pull from Docker registry
#
# Enroot is NVIDIA's HPC container runtime, optimized for:
# - Unprivileged container execution
# - GPU workloads with native NVIDIA support
# - Slurm integration via pyxis plugin
#
# Build Modes:
#   local    - Build Docker image locally, then convert to squashfs (requires Docker)
#   registry - Pull image directly from Docker registry (no Docker required)
#
# Shared Mode:
#   Set SHARED_PATH to install to a shared location for all users
#   Example: SHARED_PATH=/shared/containers ./Enroot.sh
#
# The script auto-detects Docker availability and falls back to registry mode if needed.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
IMAGE_NAME="${IMAGE_NAME:-kasmvnc-ubuntu}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Shared installation path (optional)
# Set SHARED_PATH to install to a shared location accessible by all users
SHARED_PATH="${SHARED_PATH:-}"

# Determine output file location
if [ -n "$SHARED_PATH" ]; then
    # Shared mode: install to shared location
    mkdir -p "$SHARED_PATH" 2>/dev/null || true
    SQSH_FILE="${SHARED_PATH}/${IMAGE_NAME}.sqsh"
else
    SQSH_FILE="${SQSH_FILE:-${IMAGE_NAME}.sqsh}"
fi

# Docker registry for pulling pre-built images (used in registry mode)
# Format: namespace/image for Docker Hub, or registry/namespace/image for others
# Note: For Docker Hub, do NOT include "docker.io/" prefix - Enroot doesn't want it
DOCKER_REGISTRY="${DOCKER_REGISTRY:-parallelworks/kasmvnc-ubuntu}"

# Build mode: "local" (build with Docker) or "registry" (pull from registry)
# If not set, auto-detect based on Docker availability
BUILD_MODE="${BUILD_MODE:-}"

# Auto-detect build mode if not specified
if [ -z "$BUILD_MODE" ]; then
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        BUILD_MODE="local"
    else
        BUILD_MODE="registry"
    fi
fi

# Force rebuild even if sqsh exists (set FORCE=true to override)
FORCE="${FORCE:-false}"

# Get absolute path for output file
if [[ "${SQSH_FILE}" != /* ]]; then
    SQSH_FILE_ABS="$(pwd)/${SQSH_FILE}"
else
    SQSH_FILE_ABS="${SQSH_FILE}"
fi

echo "=== Enroot Container Builder ==="
echo "Build mode: ${BUILD_MODE}"
echo "Output file: ${SQSH_FILE_ABS}"
echo ""

# Check if sqsh file already exists
if [ -f "${SQSH_FILE}" ] && [ "$FORCE" != "true" ]; then
    echo "=== Existing container found ==="
    echo "File: ${SQSH_FILE_ABS}"
    echo "Size: $(du -h "${SQSH_FILE}" | cut -f1)"
    echo "Date: $(stat -c %y "${SQSH_FILE}" 2>/dev/null || stat -f %Sm "${SQSH_FILE}" 2>/dev/null)"
    echo ""
    echo "Skipping build. To force rebuild, run: FORCE=true ./Enroot.sh"
    echo ""
    echo "=== Enroot Runtime Examples ==="
    echo ""
    echo "# Create container instance:"
    echo "  enroot create --name ${IMAGE_NAME} ${SQSH_FILE}"
    echo ""
    echo "# Basic run:"
    echo "  enroot start ${IMAGE_NAME}"
    exit 0
fi

# Remove existing squashfs file if force rebuild
if [ -f "${SQSH_FILE}" ]; then
    echo "Removing existing ${SQSH_FILE}..."
    rm -f "${SQSH_FILE}"
fi

if [ "$BUILD_MODE" = "local" ]; then
    # Local mode: Build Docker image and convert to squashfs
    echo "=== Building from local Dockerfile ==="
    echo "Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""

    echo "Step 1: Building Docker image..."
    docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" -f "${SCRIPT_DIR}/Dockerfile.ubuntu" "${SCRIPT_DIR}"

    echo ""
    echo "Step 2: Converting Docker image to Enroot squashfs..."
    enroot import -o "${SQSH_FILE}" "dockerd://${IMAGE_NAME}:${IMAGE_TAG}"

elif [ "$BUILD_MODE" = "registry" ]; then
    # Registry mode: Pull directly from Docker registry
    # Strip docker.io/ prefix if present - Enroot doesn't want it for Docker Hub
    ENROOT_REGISTRY="${DOCKER_REGISTRY#docker.io/}"
    REGISTRY_IMAGE="${ENROOT_REGISTRY}:${IMAGE_TAG}"
    echo "=== Pulling from Docker registry ==="
    echo "Registry image: ${REGISTRY_IMAGE}"
    echo ""
    echo "Note: This requires the image to be pre-built and pushed to the registry."
    echo ""

    echo "Importing image from registry to Enroot squashfs..."
    enroot import -o "${SQSH_FILE}" "docker://${REGISTRY_IMAGE}"

else
    echo "ERROR: Invalid BUILD_MODE '${BUILD_MODE}'. Must be 'local' or 'registry'."
    exit 1
fi

echo ""
echo "=== Build complete ==="
echo "Enroot container: ${SQSH_FILE_ABS}"
echo ""

if [ -n "$SHARED_PATH" ]; then
    echo "=== SHARED INSTALLATION ==="
    echo "Container installed to shared location: ${SQSH_FILE_ABS}"
    echo ""
    echo "Users can run directly from the shared sqsh file without creating their own copy."
    echo ""
    echo "=== User Instructions (share with users) ==="
    echo ""
    echo "# Run directly from shared container (no setup needed):"
    echo "  enroot start --rw ${SQSH_FILE_ABS} /bin/bash"
    echo ""
    echo "# Run with desktop environment:"
    echo "  enroot start --rw \\"
    echo "      -e HOME=/tmp/\$USER-kasmhome \\"
    echo "      -e BASE_PATH=/ \\"
    echo "      -e NGINX_PORT=8080 \\"
    echo "      ${SQSH_FILE_ABS} /usr/local/bin/run_kasm_nginx.sh"
    echo ""
    echo "# With Slurm (via pyxis plugin):"
    echo "  srun --container-image=${SQSH_FILE_ABS} \\"
    echo "       --container-mounts=/etc/passwd:/etc/passwd:ro,/etc/group:/etc/group:ro \\"
    echo "       --container-env=BASE_PATH=/me/session/\$USER/desktop/ \\"
    echo "       /usr/local/bin/run_kasm_nginx.sh"
    echo ""
    echo "=== Notes ==="
    echo "- Users do NOT need to run enroot import or enroot create"
    echo "- Each user runs from the same shared sqsh file"
    echo "- User data is isolated via HOME=/tmp/\$USER-kasmhome"
else
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
    echo "  srun --container-image=${SQSH_FILE_ABS} \\"
    echo "       --container-mounts=/etc/passwd:/etc/passwd:ro,/etc/group:/etc/group:ro \\"
    echo "       --container-env=BASE_PATH=/me/session/user/desktop/ \\"
    echo "       /usr/local/bin/run_kasm_nginx.sh"
    echo ""
    echo "=== Notes ==="
    echo "- Enroot runs as your UID/GID by default (like Singularity)"
    echo "- Use --rw flag if you need a writable container"
    echo "- For Slurm integration, ensure pyxis plugin is installed"
    echo "- GPU support requires nvidia-container-cli"
    echo ""
    echo "=== Shared Installation ==="
    echo "To install for all users, set SHARED_PATH:"
    echo "  SHARED_PATH=/shared/containers ./Enroot.sh"
fi
