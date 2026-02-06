#!/bin/bash
#
# Build and optionally push the KasmVNC Rocky 9 Docker container
#
# Usage:
#   ./Docker-rocky9.sh              # Build only
#   ./Docker-rocky9.sh --push       # Build and push to registry
#   ./Docker-rocky9.sh --push --tag v1.0.0  # Build and push with specific tag
#
# Environment variables:
#   IMAGE_NAME      - Local image name (default: kasmvnc-rocky9)
#   IMAGE_TAG       - Image tag (default: latest)
#   DOCKER_REGISTRY - Registry path (default: docker.io/parallelworks/kasmvnc-rocky9)
#   PUSH            - Set to 'true' to push (alternative to --push flag)
#   PUSH_LATEST     - Also push :latest when pushing versioned tag (default: true)
#

set -e

# Configuration
IMAGE_NAME="${IMAGE_NAME:-kasmvnc-rocky9}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io/parallelworks/kasmvnc-rocky9}"
PUSH="${PUSH:-false}"
PUSH_LATEST="${PUSH_LATEST:-true}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --push)
            PUSH="true"
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
            PUSH_LATEST="false"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--push] [--tag TAG] [--registry URL] [--no-latest]"
            exit 1
            ;;
    esac
done

echo "=== Docker Build Script (Rocky 9) ==="
echo "Local image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Registry: ${DOCKER_REGISTRY}"
echo "Push: ${PUSH}"
echo ""

# Step 1: Build Docker image
echo "=== Step 1: Building Docker image ==="
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" -f Dockerfile.rocky9 .

if [ "$PUSH" = "true" ]; then
    # Step 2: Tag for registry
    echo ""
    echo "=== Step 2: Tagging for registry ==="
    docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${DOCKER_REGISTRY}:${IMAGE_TAG}"
    echo "Tagging: ${DOCKER_REGISTRY}:${IMAGE_TAG}"

    # Also tag as latest if pushing a versioned tag
    if [ "$IMAGE_TAG" != "latest" ] && [ "$PUSH_LATEST" = "true" ]; then
        docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${DOCKER_REGISTRY}:latest"
        echo "Tagging: ${DOCKER_REGISTRY}:latest"
    fi

    # Step 3: Push to registry
    echo ""
    echo "=== Step 3: Pushing to registry ==="
    echo "Pushing: ${DOCKER_REGISTRY}:${IMAGE_TAG}"
    docker push "${DOCKER_REGISTRY}:${IMAGE_TAG}"

    if [ "$IMAGE_TAG" != "latest" ] && [ "$PUSH_LATEST" = "true" ]; then
        echo "Pushing: ${DOCKER_REGISTRY}:latest"
        docker push "${DOCKER_REGISTRY}:latest"
    fi

    echo ""
    echo "=== Build complete ==="
    echo "Local image: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo "Pushed to: ${DOCKER_REGISTRY}:${IMAGE_TAG}"
else
    echo ""
    echo "=== Build complete ==="
    echo "Local image: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo ""
    echo "To push to registry, run:"
    echo "  $0 --push"
fi

echo ""
echo "=== Local Usage ==="
echo ""
echo "# Run locally with Docker:"
echo "  docker run -p 8080:8080 ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "# Run with custom base path:"
echo "  docker run -p 8080:8080 -e BASE_PATH=/desktop/ ${IMAGE_NAME}:${IMAGE_TAG}"

if [ "$PUSH" = "true" ]; then
    echo ""
    echo "=== Pull from Registry ==="
    echo ""
    echo "# Pull the image:"
    echo "  docker pull ${DOCKER_REGISTRY}:${IMAGE_TAG}"
    echo ""
    echo "# Use with Enroot (no Docker required on target):"
    echo "  BUILD_MODE=registry DOCKER_REGISTRY=${DOCKER_REGISTRY} IMAGE_NAME=kasmvnc-rocky9 ./Enroot.sh"
fi
