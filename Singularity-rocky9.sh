#!/bin/bash
#
# Build a Singularity container from the KasmVNC Rocky 9 Docker image
#
# Usage:
#   ./Singularity-rocky9.sh                    # Build SIF from local Docker image
#   BUILD_SANDBOX=true ./Singularity-rocky9.sh # Build as sandbox directory
#
# Shared Mode:
#   Set SHARED_PATH to install to a shared location for all users
#   Example: SHARED_PATH=/shared/containers ./Singularity-rocky9.sh
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
IMAGE_NAME="${IMAGE_NAME:-kasmvnc-rocky9}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
BUILD_SANDBOX="${BUILD_SANDBOX:-false}"
FORCE="${FORCE:-false}"

# Shared installation path (optional)
SHARED_PATH="${SHARED_PATH:-}"

# Determine output file location
if [ -n "$SHARED_PATH" ]; then
    mkdir -p "$SHARED_PATH" 2>/dev/null || true
    if [ "$BUILD_SANDBOX" = "true" ]; then
        SIF_FILE="${SHARED_PATH}/${IMAGE_NAME}"
    else
        SIF_FILE="${SHARED_PATH}/${IMAGE_NAME}.sif"
    fi
else
    if [ "$BUILD_SANDBOX" = "true" ]; then
        SIF_FILE="${SIF_FILE:-${IMAGE_NAME}}"
    else
        SIF_FILE="${SIF_FILE:-${IMAGE_NAME}.sif}"
    fi
fi

# Get absolute path
if [[ "${SIF_FILE}" != /* ]]; then
    SIF_FILE_ABS="$(pwd)/${SIF_FILE}"
else
    SIF_FILE_ABS="${SIF_FILE}"
fi

echo "=== Building Singularity Container (Rocky 9) ==="
echo "Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Output: ${SIF_FILE_ABS}"
echo "Build sandbox: ${BUILD_SANDBOX}"
echo ""

# Check if file already exists
if [ -e "${SIF_FILE}" ] && [ "$FORCE" != "true" ]; then
    echo "=== Existing container found ==="
    echo "Path: ${SIF_FILE_ABS}"
    if [ -d "${SIF_FILE}" ]; then
        echo "Type: Sandbox directory"
        echo "Size: $(du -sh "${SIF_FILE}" | cut -f1)"
    else
        echo "Type: SIF file"
        echo "Size: $(du -h "${SIF_FILE}" | cut -f1)"
    fi
    echo ""
    echo "Skipping build. To force rebuild: FORCE=true ./Singularity-rocky9.sh"
    echo ""
    echo "=== Usage ==="
    echo ""
    echo "singularity run ${SIF_FILE_ABS}"
    exit 0
fi

# Step 1: Build Docker image
echo "Step 1: Building Docker image..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" -f "${SCRIPT_DIR}/Dockerfile.rocky9" "${SCRIPT_DIR}"

# Step 2: Convert to Singularity
echo ""
echo "Step 2: Converting Docker image to Singularity..."

if [ -e "${SIF_FILE}" ]; then
    echo "Removing existing ${SIF_FILE}..."
    rm -rf "${SIF_FILE}"
fi

if [ "$BUILD_SANDBOX" = "true" ]; then
    singularity build --sandbox "${SIF_FILE}" "docker-daemon://${IMAGE_NAME}:${IMAGE_TAG}"
else
    singularity build "${SIF_FILE}" "docker-daemon://${IMAGE_NAME}:${IMAGE_TAG}"
fi

echo ""
echo "=== Build complete ==="
echo "Singularity container: ${SIF_FILE_ABS}"
if [ -d "${SIF_FILE}" ]; then
    echo "Type: Sandbox directory"
    echo "Size: $(du -sh "${SIF_FILE}" | cut -f1)"
else
    echo "Type: SIF file"
    echo "Size: $(du -h "${SIF_FILE}" | cut -f1)"
fi
echo ""

if [ -n "$SHARED_PATH" ]; then
    echo "=== SHARED INSTALLATION ==="
    echo "Container installed to shared location: ${SIF_FILE_ABS}"
    echo ""
    echo "=== User Instructions (share with users) ==="
    echo ""
    echo "# Basic run:"
    echo "  singularity run ${SIF_FILE_ABS}"
    echo ""
    echo "# With proper username resolution:"
    echo "  singularity run \\"
    echo "      --bind /etc/passwd:/etc/passwd:ro \\"
    echo "      --bind /etc/group:/etc/group:ro \\"
    echo "      ${SIF_FILE_ABS}"
    echo ""
    echo "# Behind reverse proxy:"
    echo "  singularity run \\"
    echo "      --env BASE_PATH=/me/session/\$USER/desktop/ \\"
    echo "      --bind /etc/passwd:/etc/passwd:ro \\"
    echo "      --bind /etc/group:/etc/group:ro \\"
    echo "      ${SIF_FILE_ABS}"
else
    echo "=== Usage ==="
    echo ""
    echo "# Basic run:"
    echo "  singularity run ${SIF_FILE}"
    echo ""
    echo "# With proper username resolution:"
    echo "  singularity run \\"
    echo "      --bind /etc/passwd:/etc/passwd:ro \\"
    echo "      --bind /etc/group:/etc/group:ro \\"
    echo "      ${SIF_FILE}"
    echo ""
    echo "# Full featured for HPC:"
    echo "  singularity run \\"
    echo "      --nv \\"
    echo "      --bind /etc/passwd:/etc/passwd:ro \\"
    echo "      --bind /etc/group:/etc/group:ro \\"
    echo "      --bind /scratch \\"
    echo "      --bind /home \\"
    echo "      ${SIF_FILE}"
    echo ""
    echo "# Behind reverse proxy:"
    echo "  singularity run \\"
    echo "      --env BASE_PATH=/me/session/username/desktop/ \\"
    echo "      --bind /etc/passwd:/etc/passwd:ro \\"
    echo "      --bind /etc/group:/etc/group:ro \\"
    echo "      ${SIF_FILE}"
fi
