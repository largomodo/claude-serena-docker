#!/bin/bash
# Container launch script for all claude-env variants.
# Usage: ./launch.sh <variant> <host_path> [image_tag]
#   variant:   java | c | c-pico | x86 | snes | 68k | image-dev | java-docker | java-angular | gowin | kicad
#   host_path: host directory mounted to /workspace in the container
#   image_tag: image tag (default: latest)

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Shell-exported values take precedence over .env values.
_TOKEN_BEFORE="${CLAUDE_CODE_OAUTH_TOKEN:-}"
[ -f "$SCRIPT_DIR/.env" ] && . "$SCRIPT_DIR/.env"
[ -n "$_TOKEN_BEFORE" ] && CLAUDE_CODE_OAUTH_TOKEN="$_TOKEN_BEFORE"
unset _TOKEN_BEFORE

TAG="latest"

if [ $# -lt 2 ]; then
    echo "Usage: $0 <variant> <host_path> [image_tag]"
    echo "  variant:   One of: java, c, c-pico, x86, snes, 68k, image-dev, java-docker, java-angular, gowin, kicad"
    echo "  host_path: Path on host to mount to /workspace in container"
    echo "  image_tag: Optional image tag (default: latest)"
    exit 1
fi

VARIANT="$1"
HOST_PATH="$2"

if [ $# -eq 3 ]; then
    TAG="$3"
fi

IMAGE_NAME="claude-env-${VARIANT}"

if [ ! -d "$HOST_PATH" ]; then
    echo "Error: Directory '$HOST_PATH' does not exist"
    exit 1
fi

ABSOLUTE_PATH=$(cd "$HOST_PATH" && pwd)
PROJECT_NAME=$(basename "$ABSOLUTE_PATH")

PERSIST_DIR="$ABSOLUTE_PATH/.claudeproject"

mkdir -p "$PERSIST_DIR/.claude"
mkdir -p "$PERSIST_DIR/.serena"
touch "$PERSIST_DIR/.bash_history"

# Variant-specific host directory setup
VARIANT_MOUNTS=()
TTYACM_ARGS=()
PICO_EXTRA_ARGS=()
SECURITY_ARGS=()
PORT_ARGS=()
case "$VARIANT" in
    java)
        mkdir -p "$PERSIST_DIR/.m2"
        VARIANT_MOUNTS=(-v "$PERSIST_DIR/.m2:/home/codeuser/.m2")
        ;;
    c-pico)
        for dev in /dev/ttyACM*; do
            [ -e "$dev" ] && TTYACM_ARGS+=("--device=$dev")
        done
        PICO_EXTRA_ARGS=(-v /dev/bus/usb:/dev/bus/usb -v /run/udev:/run/udev:ro "--device-cgroup-rule=c 189:* rmw" "--device-cgroup-rule=c 166:* rmw")
        ;;
    # Tang Nano 4K uses a BL702-based USB bridge (Sipeed VID 0x28e9 primary, FTDI VID 0x0403 variant). (ref: DL-004)
    # 189=USB bus devices, 166=ACM serial, 188=ttyUSB serial. /run/udev:ro provides udev events for openFPGALoader.
    # Both ttyACM* and ttyUSB* scanned: BL702 may present as either CDC-ACM or FTDI class.
    # PICO_EXTRA_ARGS is shared with docker run expansion; all variants use ${PICO_EXTRA_ARGS[@]}.
    gowin)
        for dev in /dev/ttyACM*; do
            [ -e "$dev" ] && TTYACM_ARGS+=("--device=$dev")
        done
        for dev in /dev/ttyUSB*; do
            # ttyUSB: major 188; cgroup rule below enables access when device is present.
            [ -e "$dev" ] && TTYACM_ARGS+=("--device=$dev")
        done
        PICO_EXTRA_ARGS=(-v /dev/bus/usb:/dev/bus/usb -v /run/udev:/run/udev:ro "--device-cgroup-rule=c 189:* rmw" "--device-cgroup-rule=c 166:* rmw" "--device-cgroup-rule=c 188:* rmw")
        ;;
    image-dev)
        SECURITY_ARGS=(--cap-add SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined --device /dev/fuse --device /dev/net/tun)
        ;;
    java-docker)
        mkdir -p "$PERSIST_DIR/.m2"
        # Pre-created (unlike image-dev's ephemeral storage) so Testcontainers/Dev Services image pulls
        # survive a relaunch, and to avoid a subuid-ownership race where the in-container rootless
        # dockerd's first mkdir/chown into the data-root would otherwise be denied.
        mkdir -p "$PERSIST_DIR/docker"
        VARIANT_MOUNTS=(-v "$PERSIST_DIR/.m2:/home/codeuser/.m2" -v "$PERSIST_DIR/docker:/home/codeuser/.local/share/docker")
        # Same privileges as image-dev's rootless Docker-in-Docker; confined to this variant's
        # launch so plain java-variant use stays unprivileged.
        SECURITY_ARGS=(--cap-add SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined --device /dev/fuse --device /dev/net/tun)
        # Testcontainers reaches inner mapped ports over the dev container's own loopback and needs
        # no publishing; these two ports are published only so `mvn quarkus:dev` and an attached
        # debugger can reach the container from the host.
        PORT_ARGS=(-p 8080:8080 -p 5005:5005)
        ;;
    # Fullstack variant: java toolchain + Angular CLI, named for what it contains
    # rather than its role. (ref: DL-010)
    java-angular)
        mkdir -p "$PERSIST_DIR/.m2"
        # ~/.npm is a pure redownload cache -- persisting it makes every npm ci
        # after the first fast and network-independent, mirroring .m2. (ref: DL-009)
        mkdir -p "$PERSIST_DIR/.npm"
        VARIANT_MOUNTS=(-v "$PERSIST_DIR/.m2:/home/codeuser/.m2" -v "$PERSIST_DIR/.npm:/home/codeuser/.npm")
        # 4200: ng serve (requires --host 0.0.0.0, see README); 8080: Java backend;
        # 5005: JVM debugger (mirrors java-docker's rationale; fixed ports collide
        # across concurrent instances -- same accepted tradeoff). (ref: DL-009)
        PORT_ARGS=(-p 4200:4200 -p 8080:8080 -p 5005:5005)
        ;;
esac

echo "Launching container with mounted path: $ABSOLUTE_PATH"
echo "Project name: $PROJECT_NAME"
echo "Image: ${IMAGE_NAME}:${TAG}"

CLAUDE_JSON_MOUNTS=()
if [ -f "$PERSIST_DIR/.claude.json" ] \
    && grep -q '"hasCompletedOnboarding": true' "$PERSIST_DIR/.claude.json" 2>/dev/null; then
    echo "Detected existing Claude Code credentials -- mounting .claude.json"
    CLAUDE_JSON_MOUNTS=(-v "$PERSIST_DIR/.claude.json:/home/codeuser/.claude.json")
else
    echo "First launch -- .claude.json will be created by Claude Code inside the container"
fi

OAUTH_TOKEN_ARGS=()
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    OAUTH_TOKEN_ARGS=(-e "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN")
fi

docker run -it --rm \
    -v "$ABSOLUTE_PATH:/workspace" \
    -v "$PERSIST_DIR/.claude:/home/codeuser/.claude" \
    -v "$PERSIST_DIR/.serena:/home/codeuser/.serena" \
    -v "$PERSIST_DIR/.bash_history:/home/codeuser/.bash_history" \
    "${VARIANT_MOUNTS[@]}" \
    "${CLAUDE_JSON_MOUNTS[@]}" \
    "${OAUTH_TOKEN_ARGS[@]}" \
    -e "PROJECT_NAME=$PROJECT_NAME" \
    -e "VARIANT=$VARIANT" \
    -p 24282:24282 \
    --init \
    "${TTYACM_ARGS[@]}" \
    "${PICO_EXTRA_ARGS[@]}" \
    "${SECURITY_ARGS[@]}" \
    "${PORT_ARGS[@]}" \
    "${IMAGE_NAME}:${TAG}"
