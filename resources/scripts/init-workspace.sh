#!/bin/bash
set -e

# Configuration Constants
WORKSPACE_DIR="/workspace"
PERSIST_DIR="/workspace/.claudeproject"
TEMPLATE_DIR="/usr/local/share/claude-env"
HOME_DIR="/home/codeuser"
CLAUDE_CONFIG_REPO="https://github.com/largomodo/claude-config.git"

# Order determines detection priority - first match wins. C/C++ is checked first.
# cpp is Serena's language identifier for both C and C++ via clangd. (DL-004)
# Adding a language: append "lang:*.ext" to the array. Detection cost is O(languages) find calls. (ref: DL-004)
LANG_EXTENSIONS=(
    "cpp:*.c"
    "cpp:*.h"
    "cpp:*.cpp"
    "python:*.py"
    "go:*.go"
    "rust:*.rs"
    "typescript:*.ts"
)

echo "=== Initializing Workspace (Runtime Provisioning) ==="

# launch.sh pre-creates .claude and .serena on the host and bind-mounts
# them before container start, so home directory paths and persistence paths are
# the same filesystem location -- no symlink indirection is needed.

# 1. Setup Persistence Root
if [ ! -d "$PERSIST_DIR" ]; then
    echo "Creating persistence directory..."
    mkdir -p "$PERSIST_DIR"
    echo '*' > "$PERSIST_DIR/.gitignore"
fi

# 2. Provisioning

# 2a. Claude Config (Git-based)
# Detection uses .git presence rather than directory existence because the bind
# mount ensures the directory always exists, even on first launch. .git is a
# reliable marker that the clone has been completed.
if [ ! -d "$HOME_DIR/.claude/.git" ]; then
    echo "Provisioning .claude config from remote..."
    # git clone refuses non-empty directories; bind mounts create . and ..
    # entries making the target non-empty. Clone to a temp dir then move
    # contents into the mount point. shopt dotglob ensures hidden files
    # (including .git) are transferred.
    TMPCLONE=$(mktemp -d)
    if git clone --depth 1 "$CLAUDE_CONFIG_REPO" "$TMPCLONE"; then
        shopt -s dotglob
        mv "$TMPCLONE"/* "$HOME_DIR/.claude/" 2>/dev/null || true
        shopt -u dotglob
        rm -rf "$TMPCLONE"
        echo "  Successfully cloned claude-config."
    else
        rm -rf "$TMPCLONE"
        echo "  Error: Failed to clone claude-config."
        exit 1
    fi
else
    echo "Refreshing .claude config..."
    if (cd "$HOME_DIR/.claude" && git pull --rebase); then
        echo "  Config updated."
    else
        echo "  Warning: Failed to update .claude config (network issue or conflict)."
    fi
fi

# 2b. Serena Config (Template-based)
# $HOME_DIR/.serena is bind-mounted from .claudeproject/.serena, so writing here
# persists to the host filesystem without a separate copy step.
if [ ! -f "$HOME_DIR/.serena/serena_config.yml" ]; then
    echo "Provisioning Serena configuration from image..."
    if [ -f "$TEMPLATE_DIR/serena_config.yml" ]; then
        cp "$TEMPLATE_DIR/serena_config.yml" "$HOME_DIR/.serena/serena_config.yml"
        echo "  Copied serena_config.yml."
    else
        echo "  Error: Master serena_config.yml not found in $TEMPLATE_DIR"
        exit 1
    fi
fi

# 3. Handle .claude.json
# On consecutive launches, launch.sh bind-mounts .claudeproject/.claude.json to
# ~/.claude.json when "hasCompletedOnboarding": true is present in the persisted
# file. Mounting a defaults-only file would prevent Claude Code from completing
# its onboarding flow, so the check guards against premature mounting.
#
# On first launch, FIRST_LAUNCH_CLAUDE_JSON is set to true. After the interactive
# session ends, an EXIT trap copies ~/.claude.json (created by Claude Code during
# onboarding) to $PERSIST_DIR/.claude.json. The next launch will bind-mount it.
FIRST_LAUNCH_CLAUDE_JSON=false
if [ -f "$HOME_DIR/.claude.json" ]; then
    echo ".claude.json is bind-mounted -- consecutive launch."
else
    echo ".claude.json not present -- first launch. Will persist after session."
    FIRST_LAUNCH_CLAUDE_JSON=true
fi

# -------------------------------------------------------
# 4. Project Initialization Logic
#    clangd is auto-managed by Serena (SolidLSP). On each
#    launch, Serena downloads the clangd binary,
#    which can cause the first index attempt to time out.
#    (RSK-001) We retry up to 2 times with a short pause
#    between attempts to allow the download to complete.
#    (DL-003)
# -------------------------------------------------------
serena_index_with_retry() {
    local max_attempts=2  # 2 not 3: clangd lacks JVM warmup delay; only first-download latency needs a retry. (DL-003)
    local attempt=1
    local delay=5

    while [ $attempt -le $max_attempts ]; do
        echo "  Indexing attempt $attempt of $max_attempts..."
        if serena project index 2>&1; then
            echo "  Indexing succeeded on attempt $attempt."
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            echo "  Indexing failed. Retrying in ${delay}s..."
            sleep "$delay"
        fi
        attempt=$((attempt + 1))
    done

    echo "  Warning: Indexing failed after $max_attempts attempts."
    return 1
}

cd "$WORKSPACE_DIR"

# Check if this is the first time (no .serena directory in workspace)
# Note: We just provisioned .serena in .claudeproject, but we also check for project-specific index
if [ ! -f ".serena/project.yml" ]; then
    echo "Checking for project initialization..."

    # Detect source language from first matching extension
    detected_lang=""
    for entry in "${LANG_EXTENSIONS[@]}"; do
        lang="${entry%%:*}"
        glob="${entry#*:}"
        if find . -maxdepth 12 -name "$glob" -type f | head -n 1 | grep -q .; then
            detected_lang="$lang"
            break
        fi
    done
    if [ -n "$detected_lang" ]; then
        echo "$detected_lang source files detected, creating $detected_lang project..."
        serena project create --language "$detected_lang" || echo "Warning: Failed to create project"
        echo "Indexing project..."
        serena_index_with_retry || echo "Warning: Failed to create project index"
    else
        echo "No source files detected. You can manually create the project with:"
        supported=""; for e in "${LANG_EXTENSIONS[@]}"; do supported="$supported ${e%%:*}"; done
        echo "  serena project create --language <lang> --index"
        echo "  Supported languages:$supported"
    fi
else
    echo "Project index found, updating..."
    serena_index_with_retry || echo "Warning: Failed to update index"
fi

echo "=== Workspace Ready ==="
echo ""
echo "To configure Claude Code with Serena, run:"
echo "  claude mcp add serena -- serena start-mcp-server --context ide-assistant --project /workspace"
echo ""
echo "Or start an interactive session with:"
echo "  claude"
echo ""

# Attempt to auto-configure MCP if possible (idempotent usually)
# We pipe to true to ensure failure doesn't crash the entrypoint
claude mcp add serena -- serena start-mcp-server --context ide-assistant --project /workspace >/dev/null 2>&1 || true

# On first launch, register an EXIT trap to copy ~/.claude.json to the
# persistence directory after the session ends. The next launch will then
# bind-mount the persisted file.
#
# exec would replace this shell process, making traps registered here unreachable.
# Foreground bash (without exec) preserves this shell so the EXIT trap fires
# when the user exits the session.
#
# SIGKILL bypasses all traps; docker stop (SIGTERM + 10s grace) triggers them.
# The --init flag in docker run is required for signal forwarding. (R-002, R-003)
if [ "$FIRST_LAUNCH_CLAUDE_JSON" = true ]; then
    persist_on_exit() {
        if [ -f "$HOME_DIR/.claude.json" ]; then
            cp "$HOME_DIR/.claude.json" "$PERSIST_DIR/.claude.json"
            echo "Persisted .claude.json for next launch."
        fi
    }
    trap persist_on_exit EXIT
fi

if [ "$#" -gt 0 ]; then
    "$@"
else
    bash
fi
