#!/bin/bash
# Two-phase build: (1) docker build Dockerfile.base -> claude-env-base:<tag>,
# then (2) docker compose build variant images (FROM claude-env-base).
#
# Usage:
#   ./build.sh                     -- build base then all 7 variants
#   ./build.sh <tag>               -- build base:<tag> then all variants with that tag
#   ./build.sh <tag> <variant>     -- build base:<tag> then the named variant service only

set -e

TAG="latest"
BASE_IMAGE="claude-env-base"

if [ $# -ge 1 ]; then
    TAG="$1"
fi

VARIANT_ARG=""
if [ $# -ge 2 ]; then
    VARIANT_ARG="$2"
fi

USER_UID=$(id -u)
USER_GID=$(id -g)

echo "Building base image: ${BASE_IMAGE}:${TAG}"
docker build \
    -f Dockerfile.base \
    --build-arg USER_UID=$USER_UID \
    --build-arg USER_GID=$USER_GID \
    -t "${BASE_IMAGE}:${TAG}" .

echo "Base build completed: ${BASE_IMAGE}:${TAG}"

if [ -f docker-compose.yml ]; then
    if [ -n "$VARIANT_ARG" ]; then
        echo "Building variant: $VARIANT_ARG"
        docker compose build \
            --build-arg BASE_TAG=$TAG \
            --build-arg USER_UID=$USER_UID \
            --build-arg USER_GID=$USER_GID \
            "$VARIANT_ARG"
    else
        echo "Building all variants..."
        docker compose build \
            --build-arg BASE_TAG=$TAG \
            --build-arg USER_UID=$USER_UID \
            --build-arg USER_GID=$USER_GID
    fi
    echo "Variant build(s) completed."
fi
