#!/bin/bash

set -e

IMAGE_NAME="claude-env"
TAG="latest"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <host_path> [image_tag]"
    echo "  host_path: Path on host to mount to /workspace in container"
    echo "  image_tag: Optional image tag (default: latest)"
    exit 1
fi

HOST_PATH="$1"

if [ $# -eq 2 ]; then
    TAG="$2"
fi

if [ ! -d "$HOST_PATH" ]; then
    echo "Error: Directory '$HOST_PATH' does not exist"
    exit 1
fi

ABSOLUTE_PATH=$(cd "$HOST_PATH" && pwd)
PROJECT_NAME=$(basename "$ABSOLUTE_PATH")

echo "Launching container with mounted path: $ABSOLUTE_PATH"
echo "Project name: $PROJECT_NAME"
echo "Image: ${IMAGE_NAME}:${TAG}"

# Run the container with the workspace mounted
# The Dockerfile's ENTRYPOINT will handle initialization
docker run -it --rm \
    -v "$ABSOLUTE_PATH:/workspace" \
    -e "PROJECT_NAME=$PROJECT_NAME" \
    -p 24282:24282 \
    --init \
    "${IMAGE_NAME}:${TAG}"