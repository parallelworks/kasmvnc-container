#!/bin/bash
#
# Build a Singularity container from the Dockerfile
#
# HPC Considerations:
# - Build on a system where you have root/Docker access, then transfer the .sif
# - SIF files are portable and don't require root to RUN (only to BUILD)
# - Use --sandbox format if squashfs is unavailable on target system
#
# Shared Mode:
#   Set SHARED_PATH to install to a shared location for all users
#   Example: SHARED_PATH=/shared/containers ./Singularity.sh
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
IMAGE_NAME="${IMAGE_NAME:-kasmvnc-ubuntu}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
BUILD_SANDBOX="${BUILD_SANDBOX:-false}"  # Set to 'true' for directory format
FORCE="${FORCE:-false}"  # Force rebuild even if exists

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

echo "=== Building Singularity Container (Ubuntu 24.04) ==="
echo "Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Output file: ${SIF_FILE_ABS}"
echo ""

# Check if file already exists
if [ -f "${SIF_FILE}" ] && [ "$FORCE" != "true" ]; then
    echo "=== Existing container found ==="
    echo "File: ${SIF_FILE_ABS}"
    echo "Size: $(du -h "${SIF_FILE}" | cut -f1)"
    echo ""
    echo "Skipping build. To force rebuild: FORCE=true ./Singularity-ubuntu.sh"
    echo ""
    if [ -n "$SHARED_PATH" ]; then
        echo "=== User Instructions (share with users) ==="
        echo ""
        echo "# Run directly (no setup needed):"
        echo "  singularity run ${SIF_FILE_ABS}"
        echo ""
        echo "# With GPU:"
        echo "  singularity run --nv ${SIF_FILE_ABS}"
    fi
    exit 0
fi

# Step 1: Build Docker image
echo "Step 1: Building Docker image..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" -f "${SCRIPT_DIR}/Dockerfile.ubuntu" "${SCRIPT_DIR}"

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
    echo "Singularity container: ${SIF_FILE_ABS}"
fi

CONTAINER="${SIF_FILE_ABS:-${IMAGE_NAME}_sandbox}"

echo ""

if [ -n "$SHARED_PATH" ]; then
    echo "=== SHARED INSTALLATION ==="
    echo "Container installed to shared location: ${SIF_FILE_ABS}"
    echo ""
    echo "Users can run directly - no setup needed. Singularity maps UID/GID automatically."
    echo ""
    echo "=== User Instructions (share with users) ==="
    echo ""
    echo "# Basic run:"
    echo "  singularity run ${CONTAINER}"
    echo ""
    echo "# With proper username resolution:"
    echo "  singularity run \\"
    echo "      --bind /etc/passwd:/etc/passwd:ro \\"
    echo "      --bind /etc/group:/etc/group:ro \\"
    echo "      ${CONTAINER}"
    echo ""
    echo "# With GPU support:"
    echo "  singularity run --nv \\"
    echo "      --bind /etc/passwd:/etc/passwd:ro \\"
    echo "      --bind /etc/group:/etc/group:ro \\"
    echo "      ${CONTAINER}"
    echo ""
    echo "# With reverse proxy path:"
    echo "  singularity run \\"
    echo "      --env BASE_PATH=/me/session/\$USER/desktop/ \\"
    echo "      --env NGINX_PORT=8080 \\"
    echo "      --bind /etc/passwd:/etc/passwd:ro \\"
    echo "      --bind /etc/group:/etc/group:ro \\"
    echo "      ${CONTAINER}"
    echo ""
    echo "=== Notes ==="
    echo "- Singularity automatically runs as your UID/GID (not root)"
    echo "- Users do NOT need to build or pull the container"
    echo "- No FUSE or special permissions needed"
else
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
    echo "=== Notes ==="
    echo "- Singularity automatically runs as YOUR UID/GID (verify with 'id' command inside)"
    echo "- Bind-mounting /etc/passwd makes 'whoami' show your real username"
    echo "- The container uses NGINX_PORT=8080 by default, set env var to change"
    echo "- Access the desktop at: http://<hostname>:8080/"
    echo ""
    echo "=== Shared Installation ==="
    echo "To install for all users, set SHARED_PATH:"
    echo "  SHARED_PATH=/shared/containers ./Singularity-ubuntu.sh"
fi
