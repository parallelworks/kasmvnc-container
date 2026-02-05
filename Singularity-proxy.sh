#!/bin/bash
#
# Build a Singularity container for the lightweight KasmVNC proxy
#
# This creates a minimal container with just Nginx for proxying to
# an existing KasmVNC instance on the host.
#
# Shared Mode:
#   Set SHARED_PATH to install to a shared location for all users
#   Example: SHARED_PATH=/shared/containers ./Singularity-proxy.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for singularity, try module load if not found
if ! command -v singularity &> /dev/null; then
    echo "Singularity not found, trying 'module load singularity'..."
    if command -v module &> /dev/null; then
        module load singularity 2>/dev/null || module load apptainer 2>/dev/null || true
    fi
    # Check again
    if ! command -v singularity &> /dev/null && ! command -v apptainer &> /dev/null; then
        echo "ERROR: Singularity/Apptainer not found. Please install or load the module."
        echo "Try: module load singularity"
        echo "  or: module load apptainer"
        exit 1
    fi
fi

# Use apptainer if singularity isn't available (they're compatible)
if ! command -v singularity &> /dev/null && command -v apptainer &> /dev/null; then
    alias singularity=apptainer
    shopt -s expand_aliases
fi

# Configuration
IMAGE_NAME="${IMAGE_NAME:-kasmproxy}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
FORCE="${FORCE:-false}"

# Shared installation path (optional)
SHARED_PATH="${SHARED_PATH:-}"

# Determine output file location
if [ -n "$SHARED_PATH" ]; then
    mkdir -p "$SHARED_PATH" 2>/dev/null || true
    SIF_FILE="${SHARED_PATH}/${IMAGE_NAME}.sif"
else
    SIF_FILE="${SIF_FILE:-${IMAGE_NAME}.sif}"
fi

# Get absolute path
if [[ "${SIF_FILE}" != /* ]]; then
    SIF_FILE_ABS="$(pwd)/${SIF_FILE}"
else
    SIF_FILE_ABS="${SIF_FILE}"
fi

echo "=== Building Singularity Proxy Container ==="
echo "Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Output file: ${SIF_FILE_ABS}"
echo ""

# Check if file already exists
if [ -f "${SIF_FILE}" ] && [ "$FORCE" != "true" ]; then
    echo "=== Existing container found ==="
    echo "File: ${SIF_FILE_ABS}"
    echo "Size: $(du -h "${SIF_FILE}" | cut -f1)"
    echo ""
    echo "Skipping build. To force rebuild: FORCE=true ./Singularity-proxy.sh"
    echo ""
    echo "=== Usage ==="
    echo ""
    echo "# Run proxy to host KasmVNC:"
    echo "  singularity run \\"
    echo "      --env KASM_HOST=<host-ip> \\"
    echo "      --env KASM_PORT=8443 \\"
    echo "      --env NGINX_PORT=8080 \\"
    echo "      --env BASE_PATH=/me/session/user/desktop/ \\"
    echo "      ${SIF_FILE_ABS}"
    exit 0
fi

# Step 1: Build Docker image (if not using pre-built)
echo "Step 1: Building Docker image..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" -f "${SCRIPT_DIR}/Dockerfile.proxy" "${SCRIPT_DIR}"

# Step 2: Convert to Singularity
echo ""
echo "Step 2: Converting Docker image to Singularity..."

if [ -f "${SIF_FILE}" ]; then
    echo "Removing existing ${SIF_FILE}..."
    rm -f "${SIF_FILE}"
fi

singularity build "${SIF_FILE}" "docker-daemon://${IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo "=== Build complete ==="
echo "Singularity proxy container: ${SIF_FILE_ABS}"
echo "Size: $(du -h "${SIF_FILE}" | cut -f1)"
echo ""

if [ -n "$SHARED_PATH" ]; then
    echo "=== SHARED INSTALLATION ==="
    echo "Container installed to shared location: ${SIF_FILE_ABS}"
    echo ""
    echo "=== User Instructions (share with users) ==="
    echo ""
    echo "# Run proxy to host KasmVNC:"
    echo "  singularity run \\"
    echo "      --env KASM_HOST=<host-ip> \\"
    echo "      --env KASM_PORT=8443 \\"
    echo "      --env NGINX_PORT=8080 \\"
    echo "      --env BASE_PATH=/me/session/\$USER/desktop/ \\"
    echo "      ${SIF_FILE_ABS}"
else
    echo "=== Usage ==="
    echo ""
    echo "# Run proxy to host KasmVNC (default port 8443):"
    echo "  singularity run \\"
    echo "      --env KASM_HOST=<host-ip> \\"
    echo "      --env KASM_PORT=8443 \\"
    echo "      ${SIF_FILE}"
    echo ""
    echo "# With custom BASE_PATH for reverse proxy:"
    echo "  singularity run \\"
    echo "      --env KASM_HOST=<host-ip> \\"
    echo "      --env KASM_PORT=8443 \\"
    echo "      --env NGINX_PORT=8080 \\"
    echo "      --env BASE_PATH=/me/session/user/desktop/ \\"
    echo "      ${SIF_FILE}"
    echo ""
    echo "=== Environment Variables ==="
    echo "  KASM_HOST   - Host where KasmVNC is running (default: 127.0.0.1)"
    echo "  KASM_PORT   - KasmVNC websocket port (default: 8443)"
    echo "  NGINX_PORT  - Nginx listen port (default: 8080)"
    echo "  BASE_PATH   - URL base path (default: /)"
fi
