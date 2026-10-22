#!/bin/bash
# Container launch script for all claude-env variants.
# Usage: ./launch.sh <variant> <host_path> [image_tag]
#   variant:   java | c | c-pico | x86 | snes | 68k | image-dev | java-docker | java-angular | gowin | kicad | arduino | android
#   host_path: host directory mounted to /workspace in the container
#   image_tag: image tag (default: latest)
#   android: devices are reached only through the host's adb server (no device passthrough)

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Shell-exported values take precedence over .env values.
_TOKEN_BEFORE="${CLAUDE_CODE_OAUTH_TOKEN:-}"
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/.env" ] && . "$SCRIPT_DIR/.env"
[ -n "$_TOKEN_BEFORE" ] && CLAUDE_CODE_OAUTH_TOKEN="$_TOKEN_BEFORE"
unset _TOKEN_BEFORE

TAG="latest"

# The variant list below is a hand-maintained copy of the docker-compose.yml
# service names (also hand-listed in CLAUDE.md and README.md); generating it
# from the compose file is deferred (issue-5).
usage() {
    echo "Usage: $0 <variant> <host_path> [image_tag]" >&2
    echo "  variant:   One of: java, c, c-pico, x86, snes, 68k, image-dev, java-docker, java-angular, gowin, kicad, arduino, android" >&2
    echo "  host_path: Path on host to mount to /workspace in container" >&2
    echo "  image_tag: Optional image tag (default: latest)" >&2
    exit 1
}

if [ $# -lt 2 ]; then
    usage
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
DEVICE_ARGS=()
SECURITY_ARGS=()
PORT_ARGS=()
# NETWORK_ARGS holds host-name mappings and network-related env for the
# container; the docker run line expands it for every variant.
NETWORK_ARGS=()
# DEVICE_ARGS holds device nodes, bus mounts and cgroup rules for USB and serial
# hardware; the docker run line expands it for every variant.

# Capability functions: each variant arm below is a list of calls to these.
# They append to the arrays above, which the docker run line expands.
# One function per capability defines each mount, device set and privilege set
# once. enable_serial_devices maps a major number to its /dev glob (166 to
# ttyACM*, 188 to ttyUSB*), so a variant scans only its own device nodes.
# docker run treats option order as a set, so interleaving mount, device and
# security options across arms is behavior-neutral.

# ~/.m2 holds resolved Maven artifacts; persisting it avoids re-downloading
# dependencies on every container start.
enable_maven_cache() {
    mkdir -p "$PERSIST_DIR/.m2"
    VARIANT_MOUNTS+=(-v "$PERSIST_DIR/.m2:/home/codeuser/.m2")
}

# ~/.npm is a pure redownload cache -- persisting it makes every npm ci
# after the first fast and network-independent, mirroring .m2. (ref: DL-009)
enable_npm_cache() {
    mkdir -p "$PERSIST_DIR/.npm"
    VARIANT_MOUNTS+=(-v "$PERSIST_DIR/.npm:/home/codeuser/.npm")
}

# ~/Arduino holds `arduino-cli lib install` output and persists like
# .m2/.npm. (ref: DL-005 in plan-arduino-nano.md)
enable_arduino_sketchbook() {
    mkdir -p "$PERSIST_DIR/Arduino"
    VARIANT_MOUNTS+=(-v "$PERSIST_DIR/Arduino:/home/codeuser/Arduino")
}

# blutter builds a multi-GB Dart SDK per target Dart version; persisting its
# cache like .m2/.npm keeps --rm launches from rebuilding it.
# The directory is created on the host first so docker does not create it
# root-owned.
enable_blutter_cache() {
    mkdir -p "$PERSIST_DIR/blutter"
    VARIANT_MOUNTS+=(-v "$PERSIST_DIR/blutter:/home/codeuser/.cache/blutter")
}

# Pre-created (unlike image-dev's ephemeral storage) so Testcontainers/Dev Services image pulls
# survive a relaunch, and to avoid a subuid-ownership race where the in-container rootless
# dockerd's first mkdir/chown into the data-root would otherwise be denied.
enable_docker_storage() {
    mkdir -p "$PERSIST_DIR/docker"
    VARIANT_MOUNTS+=(-v "$PERSIST_DIR/docker:/home/codeuser/.local/share/docker")
}

# Rootless Docker-in-Docker privileges, shared by image-dev and java-docker;
# confined to those launches so plain java-variant use stays unprivileged.
# SYS_ADMIN: the inner dockerd creates user and mount namespaces and mounts
#   overlay/proc filesystems, which the default capability set denies.
# seccomp=unconfined: the default profile blocks unshare/mount/setns-class
#   syscalls the inner runtime needs.
# apparmor=unconfined: the default profile denies mount operations inside the
#   container.
# systempaths=unconfined: unmasks /proc paths that the inner runtime must
#   mount a fresh /proc over.
# /dev/fuse: fuse-overlayfs storage driver when kernel overlay is unavailable
#   in a user namespace.
# /dev/net/tun: rootless networking (slirp4netns/pasta) creates a tap device
#   for the inner daemon's containers.
enable_rootless_dind() {
    SECURITY_ARGS+=(--cap-add SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined --device /dev/fuse --device /dev/net/tun)
}

# publish_ports <port>...: variants expose fixed app (8080) and debug (5005)
# ports; keeping host and container numbers equal lets README instructions
# work unchanged without per-launch port translation.
publish_ports() {
    local port
    for port in "$@"; do
        PORT_ARGS+=(-p "$port:$port")
    done
}

# publish_loopback_ports <port>...: for listeners that only host-local clients
# need (android's mitmdump behind adb reverse). Unlike publish_ports it does
# not bind every host interface, so the service is not reachable from the LAN.
# A device Wi-Fi proxy aimed at the host LAN address cannot reach such a
# port; devices connect through adb reverse.
publish_loopback_ports() {
    local port
    for port in "$@"; do
        PORT_ARGS+=(-p "127.0.0.1:$port:$port")
    done
}

# 189=USB bus devices. /run/udev:ro provides udev events for openFPGALoader.
enable_usb_bus() {
    DEVICE_ARGS+=(-v /dev/bus/usb:/dev/bus/usb -v /run/udev:/run/udev:ro "--device-cgroup-rule=c 189:* rmw")
}

# enable_serial_devices <major>...: 166=ACM serial (/dev/ttyACM*), 188=ttyUSB
# serial (/dev/ttyUSB*). Each existing node is passed through and the cgroup
# rule for the major is added so a device present at start is accessible.
# A board plugged in after this point stays invisible until the next launch:
# device passthrough happens once, at container start.
enable_serial_devices() {
    local major dev
    for major in "$@"; do
        case "$major" in
            166)
                for dev in /dev/ttyACM*; do
                    if [ -e "$dev" ]; then DEVICE_ARGS+=("--device=$dev"); fi
                done
                ;;
            188)
                for dev in /dev/ttyUSB*; do
                    if [ -e "$dev" ]; then DEVICE_ARGS+=("--device=$dev"); fi
                done
                ;;
            *)
                echo "Error: enable_serial_devices: unsupported major '$major'" >&2
                exit 1
                ;;
        esac
        DEVICE_ARGS+=("--device-cgroup-rule=c $major:* rmw")
    done
}

# Host adb server access for the android variant: no devices and no
# capabilities. The container reaches the host's adb server through
# host.docker.internal, which must be mapped explicitly on Linux. The host
# server has to listen on the docker bridge (README android Troubleshooting).
# A server bound with -L tcp:<docker0-ip>:5037 is reachable from every
# container on the default bridge and adb has no client authentication, so
# run it only for dynamic sessions and stop it with `adb kill-server`.
# ADB_HOST_SERVER (shell export or .env) overrides the image default.
# The mapping lives in NETWORK_ARGS because it is neither a device, a
# security option nor a published port, the three things DEVICE_ARGS,
# SECURITY_ARGS and PORT_ARGS are named for. Forwarding ADB_HOST_SERVER lets
# a host whose adb server listens elsewhere override the image default
# without editing this script; unset, the image default applies.
enable_host_adb() {
    NETWORK_ARGS+=(--add-host=host.docker.internal:host-gateway)
    if [ -n "${ADB_HOST_SERVER:-}" ]; then
        NETWORK_ARGS+=(-e "ADB_HOST_SERVER=$ADB_HOST_SERVER")
    fi
}

case "$VARIANT" in
    java)
        enable_maven_cache
        ;;
    c-pico)
        enable_usb_bus
        enable_serial_devices 166
        ;;
    # Tang Nano 4K uses a BL702-based USB bridge (Sipeed VID 0x28e9 primary, FTDI VID 0x0403 variant). (ref: DL-004)
    # Both ttyACM* and ttyUSB* scanned: BL702 may present as either CDC-ACM or FTDI class.
    gowin)
        enable_usb_bus
        enable_serial_devices 166 188
        ;;
    # Genuine Nano = FTDI FT232RL (0403:6001) and clones = CH340 (1a86:7523),
    # both ttyUSB (major 188); ttyACM (166) covers Nano Every / 33-class
    # boards. No /dev/bus/usb or /run/udev mount because bootloader upload is
    # a plain tty operation and ISP programmers are out of scope. (ref:
    # DL-008 in plan-arduino-nano.md)
    arduino)
        enable_arduino_sketchbook
        enable_serial_devices 188 166
        ;;
    image-dev)
        enable_rootless_dind
        ;;
    java-docker)
        enable_maven_cache
        enable_docker_storage
        # Same privileges as image-dev's rootless Docker-in-Docker; confined to this variant's
        # launch so plain java-variant use stays unprivileged.
        enable_rootless_dind
        # Testcontainers reaches inner mapped ports over the dev container's own loopback and needs
        # no publishing; these two ports are published only so `mvn quarkus:dev` and an attached
        # debugger can reach the container from the host.
        publish_ports 8080 5005
        ;;
    # Fullstack variant: java toolchain + Angular CLI, named for what it contains
    # rather than its role. (ref: DL-010)
    java-angular)
        enable_maven_cache
        enable_npm_cache
        # 4200: ng serve (requires --host 0.0.0.0, see README); 8080: Java backend;
        # 5005: JVM debugger (mirrors java-docker's rationale; fixed ports collide
        # across concurrent instances -- same accepted tradeoff). (ref: DL-009)
        publish_ports 4200 8080 5005
        ;;
    # Android reverse engineering: devices are reached through the host's adb
    # server, never passed through. 8080 is mitmdump's listener; devices reach
    # it with `adb reverse tcp:8080 tcp:8080`, which lands on the host's
    # loopback, so the publish binds 127.0.0.1 and mitmdump is never a
    # LAN-reachable proxy. The fixed port collides across concurrent instances
    # (same tradeoff as java-docker).
    # Static analysis needs no host adb server; only dynamic sessions do.
    android)
        enable_host_adb
        enable_blutter_cache
        publish_loopback_ports 8080
        ;;
    c|x86|snes|68k|kicad)
        ;;
    *)
        echo "Error: unknown variant '$VARIANT'" >&2
        usage
        ;;
esac

echo "Launching container with mounted path: $ABSOLUTE_PATH"
echo "Project name: $PROJECT_NAME"
echo "Image: ${IMAGE_NAME}:${TAG}"

# This is the single first-launch decision. The container never re-derives it:
# init-workspace.sh reads CLAUDE_JSON_MOUNTED to choose between the bind-mounted
# file and the EXIT-trap copy. The onboarding marker check keeps a half-written
# .claude.json from an aborted first run from being mounted over a fresh one.
CLAUDE_JSON_ARGS=()
if [ -f "$PERSIST_DIR/.claude.json" ] \
    && grep -q '"hasCompletedOnboarding": true' "$PERSIST_DIR/.claude.json" 2>/dev/null; then
    echo "Detected existing Claude Code credentials -- mounting .claude.json"
    CLAUDE_JSON_ARGS=(-v "$PERSIST_DIR/.claude.json:/home/codeuser/.claude.json" -e CLAUDE_JSON_MOUNTED=true)
else
    echo "First launch -- .claude.json will be created by Claude Code inside the container"
    CLAUDE_JSON_ARGS=(-e CLAUDE_JSON_MOUNTED=false)
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
    "${CLAUDE_JSON_ARGS[@]}" \
    "${OAUTH_TOKEN_ARGS[@]}" \
    -e "PROJECT_NAME=$PROJECT_NAME" \
    -e "VARIANT=$VARIANT" \
    -p 24282:24282 \
    --init \
    "${DEVICE_ARGS[@]}" \
    "${SECURITY_ARGS[@]}" \
    "${PORT_ARGS[@]}" \
    "${NETWORK_ARGS[@]}" \
    "${IMAGE_NAME}:${TAG}"
