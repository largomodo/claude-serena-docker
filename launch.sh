#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Source .env for defaults; shell-exported values take precedence over .env values.
_TOKEN_BEFORE="${CLAUDE_CODE_OAUTH_TOKEN:-}"
[ -f "$SCRIPT_DIR/.env" ] && . "$SCRIPT_DIR/.env"
[ -n "$_TOKEN_BEFORE" ] && CLAUDE_CODE_OAUTH_TOKEN="$_TOKEN_BEFORE"
unset _TOKEN_BEFORE

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

# Pre-create bind-mount source directories with codeuser-writable permissions before
# docker run. Docker auto-creates missing bind-mount sources as root-owned, which
# causes permission failures for the non-root codeuser inside the container. (DL-004)
PERSIST_DIR="$ABSOLUTE_PATH/.claudeproject"

mkdir -p "$PERSIST_DIR/.claude"
mkdir -p "$PERSIST_DIR/.serena"

echo "Launching container with mounted path: $ABSOLUTE_PATH"
echo "Project name: $PROJECT_NAME"
echo "Image: ${IMAGE_NAME}:${TAG}"

# Detect whether a fully-onboarded credential file exists in the persistence
# directory. Only bind-mount .claude.json when "hasCompletedOnboarding": true
# is present; mounting a defaults-only or absent file on first launch prevents
# Claude Code from completing its onboarding flow. (DL-002)
#
# Detection matches the literal JSON key-value produced by Claude CLI. If the
# field name or format changes in a future Claude release, the check falls back
# gracefully to first-launch behavior rather than crashing. (R-006)
CLAUDE_JSON_MOUNTS=()
if [ -f "$PERSIST_DIR/.claude.json" ] \
    && grep -q '"hasCompletedOnboarding": true' "$PERSIST_DIR/.claude.json" 2>/dev/null; then
    echo "Detected existing Claude Code credentials -- mounting .claude.json"
    CLAUDE_JSON_MOUNTS=(-v "$PERSIST_DIR/.claude.json:/home/codeuser/.claude.json")
else
    echo "First launch -- .claude.json will be created by Claude Code inside the container"
fi

# Build optional OAuth token argument array. An empty array expands to zero
# arguments, so the docker run invocation is unconditional.
# Shell-exported values take precedence over .env values so CI pipelines and
# one-time overrides work without modifying the .env file. (DL-004)
OAUTH_TOKEN_ARGS=()
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    OAUTH_TOKEN_ARGS=(-e "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN")
fi

# Bind-mount persistence subdirectories to their home directory counterparts.
# Empty arrays (CLAUDE_JSON_MOUNTS, OAUTH_TOKEN_ARGS) expand to zero arguments
# when not set, so the docker run line is safe with or without conditional mounts.
# --init ensures SIGTERM reaches the foreground bash process so EXIT traps fire
# on docker stop. (DL-001, R-003)
# Run the container with the workspace and persistence directories mounted
# The Dockerfile's ENTRYPOINT will handle content provisioning
docker run -it --rm \
    -v "$ABSOLUTE_PATH:/workspace" \
    -v "$PERSIST_DIR/.claude:/home/codeuser/.claude" \
    -v "$PERSIST_DIR/.serena:/home/codeuser/.serena" \
    "${CLAUDE_JSON_MOUNTS[@]}" \
    "${OAUTH_TOKEN_ARGS[@]}" \
    -e "PROJECT_NAME=$PROJECT_NAME" \
    -p 24282:24282 \
    --init \
    "${IMAGE_NAME}:${TAG}"
