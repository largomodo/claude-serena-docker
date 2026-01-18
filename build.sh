#!/bin/bash

set -e

IMAGE_NAME="claude-env"
TAG="latest"

if [ $# -eq 1 ]; then
    TAG="$1"
fi

# Get host user's UID and GID
USER_UID=$(id -u)
USER_GID=$(id -g)

echo "Building Docker image: ${IMAGE_NAME}:${TAG}"
docker build \
    --build-arg USER_UID=$USER_UID \
    --build-arg USER_GID=$USER_GID \
    -t "${IMAGE_NAME}:${TAG}" .

echo "Build completed successfully!"
echo "Image: ${IMAGE_NAME}:${TAG}"
