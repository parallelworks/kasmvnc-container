#!/bin/bash
#
# Build and optionally push the lightweight KasmVNC proxy container
#
# Usage:
#   ./Docker-proxy.sh              # Build only
#   ./Docker-proxy.sh --push       # Build and push to registry
#
# Environment Variables:
#   IMAGE_NAME      - Local image name (default: kasmproxy)
#   IMAGE_TAG       - Image tag (default: latest)
#   DOCKER_REGISTRY - Registry path (default: docker.io/parallelworks/kasmproxy)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
IMAGE_NAME="${IMAGE_NAME:-kasmproxy}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io/parallelworks/kasmproxy}"

# Parse arguments
PUSH=false
PUSH_LATEST=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH=true
            shift
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --registry)
            DOCKER_REGISTRY="$2"
            shift 2
            ;;
        --no-latest)
            PUSH_LATEST=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--push] [--tag TAG] [--registry REGISTRY] [--no-latest]"
            exit 1
            ;;
    esac
done

echo "=== Building Lightweight KasmVNC Proxy Container ==="
echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""

# Build the image
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" -f "${SCRIPT_DIR}/Dockerfile.proxy" "${SCRIPT_DIR}"

echo ""
echo "=== Build complete ==="
echo "Local image: ${IMAGE_NAME}:${IMAGE_TAG}"

# Get image size
IMAGE_SIZE=$(docker images "${IMAGE_NAME}:${IMAGE_TAG}" --format "{{.Size}}")
echo "Image size: ${IMAGE_SIZE}"

if [ "$PUSH" = "true" ]; then
    echo ""
    echo "=== Pushing to registry ==="

    # Tag for registry
    docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${DOCKER_REGISTRY}:${IMAGE_TAG}"
    echo "Tagged: ${DOCKER_REGISTRY}:${IMAGE_TAG}"

    # Push the tagged version
    docker push "${DOCKER_REGISTRY}:${IMAGE_TAG}"
    echo "Pushed: ${DOCKER_REGISTRY}:${IMAGE_TAG}"

    # Also push as :latest if requested and tag is not already 'latest'
    if [ "$PUSH_LATEST" = "true" ] && [ "$IMAGE_TAG" != "latest" ]; then
        docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${DOCKER_REGISTRY}:latest"
        docker push "${DOCKER_REGISTRY}:latest"
        echo "Pushed: ${DOCKER_REGISTRY}:latest"
    fi

    echo ""
    echo "=== Push complete ==="
    echo "Pull with: docker pull ${DOCKER_REGISTRY}:${IMAGE_TAG}"
else
    echo ""
    echo "To push to registry, run:"
    echo "  $0 --push"
    echo "  $0 --push --tag v1.0.0"
fi

echo ""
echo "=== Usage ==="
echo ""
echo "# Docker:"
echo "  docker run -p 8080:8080 -e KASM_HOST=<host-ip> -e KASM_PORT=8443 ${IMAGE_NAME}"
echo ""
echo "# With BASE_PATH:"
echo "  docker run -p 8080:8080 \\"
echo "      -e KASM_HOST=<host-ip> \\"
echo "      -e KASM_PORT=8443 \\"
echo "      -e BASE_PATH=/me/session/user/desktop/ \\"
echo "      ${IMAGE_NAME}"
echo ""
echo "# Enroot:"
echo "  enroot import -o kasmproxy.sqsh docker://${DOCKER_REGISTRY}:latest"
echo "  enroot create --name kasmproxy kasmproxy.sqsh"
echo "  enroot start -e KASM_HOST=<host-ip> -e KASM_PORT=8443 kasmproxy"
