#!/bin/bash
# Container launch script for all claude-env variants.
# Usage: ./launch.sh <variant> <host_path> [image_tag]
#   variant:   java | c | c-pico | x86 | snes | 68k | image-dev | gowin
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
    echo "  variant:   One of: java, c, c-pico, x86, snes, 68k, image-dev, gowin"
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
    "${IMAGE_NAME}:${TAG}"
