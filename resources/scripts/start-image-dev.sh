#!/bin/bash
set -e

sudo mkdir -p /run/user/$(id -u)
sudo chown $(id -u):$(id -g) /run/user/$(id -u)
export XDG_RUNTIME_DIR=/run/user/$(id -u)

echo "Starting rootless Docker daemon..."
dockerd-rootless.sh --storage-driver fuse-overlayfs &

for i in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
        echo "Docker daemon ready."
        break
    fi
    sleep 1
done

if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker daemon failed to start"
    exit 1
fi

# The backgrounded dockerd survives exec -- reparented to PID 1 (tini via --init).
# On container exit, tini sends SIGTERM for clean daemon shutdown.
exec /home/codeuser/init-workspace.sh "$@"
