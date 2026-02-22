#!/bin/bash
set -e

# Configuration Constants
WORKSPACE_DIR="/workspace"
PERSIST_DIR="/workspace/.claudeproject"
TEMPLATE_DIR="/usr/local/share/claude-env"
HOME_DIR="/home/codeuser"
CLAUDE_CONFIG_REPO="https://github.com/largomodo/claude-config.git"

# Order determines detection priority - first match wins. Java must remain first for backward compatibility.
# Adding a language: append "lang:*.ext" to the array. Detection cost is O(languages) find calls. (ref: DL-003)
LANG_EXTENSIONS=(
    "java:*.java"
    "python:*.py"
    "go:*.go"
    "rust:*.rs"
    "typescript:*.ts"
)

echo "=== Initializing Workspace (Runtime Provisioning) ==="

# Shared helper: create persist directory if absent, then symlink from home to persist.
# Args: <name> <persist_path> <home_path>
# Uses -sfn so the symlink target is the directory itself (not a path inside it).
# All three provisioning blocks (2a/2b/2c) delegate mkdir+symlink here; per-block
# setup logic (git clone/pull, template copy) stays inline because each block is
# called once — wrapping in named functions adds indirection without reuse. (ref: DL-001)
ensure_symlinked_dir() {
    local name="$1"
    local persist_path="$2"
    local home_path="$3"
    [ -d "$persist_path" ] || mkdir -p "$persist_path"
    ln -sfn "$persist_path" "$home_path"
    echo "  Provisioned $name: $home_path -> $persist_path"
}

# 1. Setup Persistence Root
if [ ! -d "$PERSIST_DIR" ]; then
    echo "Creating persistence directory..."
    mkdir -p "$PERSIST_DIR"
    echo '*' > "$PERSIST_DIR/.gitignore"
fi

# 2. Provisioning
# Each block handles its own setup (clone/copy) then calls the shared helper.
# Setup stays inline rather than in wrapper functions — see DL-001. (ref: DL-001)

# 2a. Claude Config (Git-based)
if [ ! -d "$PERSIST_DIR/.claude" ]; then
    echo "Provisioning .claude config from remote..."
    if git clone --depth 1 "$CLAUDE_CONFIG_REPO" "$PERSIST_DIR/.claude"; then
        echo "  Successfully cloned claude-config."
    else
        echo "  Error: Failed to clone claude-config."
        exit 1
    fi
else
    echo "Refreshing .claude config..."
    if (cd "$PERSIST_DIR/.claude" && git pull --rebase); then
        echo "  Config updated."
    else
        echo "  Warning: Failed to update .claude config (network issue or conflict)."
    fi
fi
ensure_symlinked_dir '.claude' "$PERSIST_DIR/.claude" "$HOME_DIR/.claude"

# 2b. Serena Config (Template-based)
if [ ! -f "$PERSIST_DIR/.serena/serena_config.yml" ]; then
    echo "Provisioning Serena configuration from image..."
    if [ -f "$TEMPLATE_DIR/serena_config.yml" ]; then
        mkdir -p "$PERSIST_DIR/.serena"
        cp "$TEMPLATE_DIR/serena_config.yml" "$PERSIST_DIR/.serena/serena_config.yml"
        echo "  Copied serena_config.yml."
    else
        echo "  Error: Master serena_config.yml not found in $TEMPLATE_DIR"
        exit 1
    fi
fi
ensure_symlinked_dir '.serena' "$PERSIST_DIR/.serena" "$HOME_DIR/.serena"

# 2c. Maven cache
ensure_symlinked_dir '.m2' "$PERSIST_DIR/.m2" "$HOME_DIR/.m2"

# 4. Handle .claude.json (Auth token + user preferences)
#
# BACKGROUND: The native Claude Code binary creates a default ~/.claude.json
# during installation (in the Docker image build). This file contains reset
# defaults (numStartups: 0, default theme, onboarding state, etc.).
#
# On container start, this installer-generated file is a real file (not a
# symlink). If we blindly move it to persistence, it overwrites the user's
# accumulated state (login credentials, preferences, startup count).
#
# The fix: only move ~/.claude.json to persistence when NO persisted version
# exists yet (genuine first run). If persistence already has the file, discard
# the installer's defaults and symlink to the persisted copy.
#
# Persists .claude.json across container restarts by symlinking $HOME_DIR/.claude.json
# to $PERSIST_DIR/.claude.json. On first run (no persisted file), moves the real file
# to persistence. On subsequent runs, discards installer-generated defaults to prevent
# overwriting accumulated credentials. Function name reflects the goal of durable
# auth state across restarts rather than the ln operation itself. (ref: DL-004)
# Uses ln -sf (not -sfn) because the target is a file, not a directory. (ref: IK-001)
persist_auth_file() {
    local persist_file="$PERSIST_DIR/.claude.json"
    local home_file="$HOME_DIR/.claude.json"

    if [ -f "$home_file" ] && [ ! -L "$home_file" ]; then
        if [ -f "$persist_file" ]; then
            # Persisted state already exists — the real file in $HOME is just
            # the installer's defaults from image build. Discard it.
            echo "Discarding installer-generated .claude.json (persisted version exists)."
            rm "$home_file"
        else
            # No persisted state yet — this is either a genuine first login or
            # the very first container launch. Preserve it.
            echo "No persisted .claude.json found. Moving current file to persistence..."
            mv "$home_file" "$persist_file"
        fi
    fi

    # If persistence has the file (either pre-existing or just moved), symlink it
    if [ -f "$persist_file" ]; then
        ln -sf "$persist_file" "$home_file"
        echo "  Symlinked .claude.json -> $persist_file"
    fi
}
persist_auth_file

# -------------------------------------------------------
# 5. Project Initialization Logic
#    jdtls has a known cold-start issue: Serena's internal
#    10s LSP request timeout is too short for the first
#    launch in a container. The first attempt fails but
#    warms jdtls internally; the second attempt succeeds
#    immediately. We retry up to 3 times with a short
#    pause between attempts.
# -------------------------------------------------------
serena_index_with_retry() {
    local max_attempts=3
    local attempt=1
    local delay=5

    while [ $attempt -le $max_attempts ]; do
        echo "  Indexing attempt $attempt of $max_attempts..."
        if serena project index 2>&1; then
            echo "  Indexing succeeded on attempt $attempt."
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            echo "  Indexing failed (jdtls cold-start timeout). Retrying in ${delay}s..."
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
        echo "Indexing project (with retry for jdtls cold-start)..."
        serena_index_with_retry || echo "Warning: Failed to create project index"
    else
        echo "No source files detected. You can manually create the project with:"
        supported=""; for e in "${LANG_EXTENSIONS[@]}"; do supported="$supported ${e%%:*}"; done
        echo "  serena project create --language <lang> --index"
        echo "  Supported languages:$supported"
    fi
else
    echo "Project index found, updating (with retry for jdtls cold-start)..."
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

# Re-persist because claude mcp add may create a fresh .claude.json that overwrites the symlink.
persist_auth_file

# If other commands were passed to `docker run`, execute them.
# Otherwise, default to starting an interactive bash shell.
if [ "$#" -gt 0 ]; then
    exec "$@"
else
    exec bash
fi
