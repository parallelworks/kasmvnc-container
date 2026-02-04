#!/bin/bash
#
# Build and optionally push Docker image to a registry
#
# This script builds the Docker image from the Dockerfile and can push it
# to Docker Hub or any other container registry.
#
# Environment Variables:
#   IMAGE_NAME     - Local image name (default: kasmvnc)
#   IMAGE_TAG      - Image tag (default: latest)
#   DOCKER_REGISTRY - Registry path to push to (e.g., docker.io/parallelworks/kasmvnc)
#   PUSH           - Set to "true" to push after building (default: false)
#   PUSH_LATEST    - Set to "true" to also push :latest tag (default: true when PUSH=true)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
IMAGE_NAME="${IMAGE_NAME:-kasmvnc}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io/parallelworks/kasmvnc}"
PUSH="${PUSH:-false}"
PUSH_LATEST="${PUSH_LATEST:-true}"

# Parse command line arguments
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
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Build and optionally push Docker image to a registry."
            echo ""
            echo "Options:"
            echo "  --push          Push image to registry after building"
            echo "  --tag TAG       Set image tag (default: latest)"
            echo "  --registry URL  Set registry path (default: docker.io/parallelworks/kasmvnc)"
            echo "  --no-latest     Don't push :latest tag (only push specified tag)"
            echo "  -h, --help      Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  IMAGE_NAME      Local image name (default: kasmvnc)"
            echo "  IMAGE_TAG       Image tag (default: latest)"
            echo "  DOCKER_REGISTRY Registry path"
            echo "  PUSH            Set to 'true' to push (default: false)"
            echo "  PUSH_LATEST     Set to 'false' to skip :latest tag"
            echo ""
            echo "Examples:"
            echo "  # Build only"
            echo "  $0"
            echo ""
            echo "  # Build and push to default registry"
            echo "  $0 --push"
            echo ""
            echo "  # Build and push with specific tag"
            echo "  $0 --push --tag v1.0.0"
            echo ""
            echo "  # Build and push to custom registry"
            echo "  $0 --push --registry ghcr.io/myorg/kasmvnc"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "=== Docker Build Script ==="
echo "Local image: ${IMAGE_NAME}:${IMAGE_TAG}"
if [ "$PUSH" = "true" ]; then
    echo "Registry: ${DOCKER_REGISTRY}"
    echo "Push: enabled"
    if [ "$IMAGE_TAG" != "latest" ] && [ "$PUSH_LATEST" = "true" ]; then
        echo "Also pushing: :latest"
    fi
else
    echo "Push: disabled (use --push to enable)"
fi
echo ""

# Step 1: Build Docker image
echo "=== Step 1: Building Docker image ==="
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" "${SCRIPT_DIR}"

# Tag for registry if we're going to push
if [ "$PUSH" = "true" ]; then
    echo ""
    echo "=== Step 2: Tagging for registry ==="

    # Tag with specified version
    REGISTRY_TAG="${DOCKER_REGISTRY}:${IMAGE_TAG}"
    echo "Tagging: ${REGISTRY_TAG}"
    docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${REGISTRY_TAG}"

    # Also tag as latest if requested and tag isn't already latest
    if [ "$IMAGE_TAG" != "latest" ] && [ "$PUSH_LATEST" = "true" ]; then
        REGISTRY_LATEST="${DOCKER_REGISTRY}:latest"
        echo "Tagging: ${REGISTRY_LATEST}"
        docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "${REGISTRY_LATEST}"
    fi

    echo ""
    echo "=== Step 3: Pushing to registry ==="
    echo "Pushing: ${REGISTRY_TAG}"
    docker push "${REGISTRY_TAG}"

    if [ "$IMAGE_TAG" != "latest" ] && [ "$PUSH_LATEST" = "true" ]; then
        echo "Pushing: ${REGISTRY_LATEST}"
        docker push "${REGISTRY_LATEST}"
    fi
fi

echo ""
echo "=== Build complete ==="
echo "Local image: ${IMAGE_NAME}:${IMAGE_TAG}"
if [ "$PUSH" = "true" ]; then
    echo "Pushed to: ${DOCKER_REGISTRY}:${IMAGE_TAG}"
    if [ "$IMAGE_TAG" != "latest" ] && [ "$PUSH_LATEST" = "true" ]; then
        echo "Pushed to: ${DOCKER_REGISTRY}:latest"
    fi
fi
echo ""
echo "=== Local Usage ==="
echo ""
echo "# Run locally with Docker:"
echo "  docker run -p 8080:8080 ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "# Run with custom base path:"
echo "  docker run -p 8080:8080 -e BASE_PATH=/desktop/ ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
if [ "$PUSH" = "true" ]; then
    echo "=== Pull from Registry ==="
    echo ""
    echo "# Pull the image:"
    echo "  docker pull ${DOCKER_REGISTRY}:${IMAGE_TAG}"
    echo ""
    echo "# Use with Enroot (no Docker required on target):"
    echo "  BUILD_MODE=registry DOCKER_REGISTRY=${DOCKER_REGISTRY} ./Enroot.sh"
    echo ""
fi
