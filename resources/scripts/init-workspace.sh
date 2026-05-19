#!/bin/bash
set -e

# Configuration Constants
WORKSPACE_DIR="/workspace"
PERSIST_DIR="/workspace/.claudeproject"
TEMPLATE_DIR="/usr/local/share/claude-env"
HOME_DIR="/home/codeuser"
CLAUDE_CONFIG_REPO="https://github.com/largomodo/claude-config.git"

# VARIANT env var is set by the variant Dockerfile (e.g., ENV VARIANT=java).
# Defaults and arrays are set in the case block below; shared logic uses them after.
LANG_EXTENSIONS=()
BINARY_EXTENSIONS=()
SERENA_MAX_ATTEMPTS=3

case "${VARIANT:-}" in
    java)
        LANG_EXTENSIONS=(
            "java:*.java"
            "python:*.py"
            "go:*.go"
            "rust:*.rs"
            "typescript:*.ts"
        )
        SERENA_MAX_ATTEMPTS=3
        ;;
    c|c-pico)
        # clangd downloads on first use; 2 attempts cover the download + index sequence.
        LANG_EXTENSIONS=(
            "cpp:*.c"
            "cpp:*.h"
            "cpp:*.cpp"
            "python:*.py"
            "go:*.go"
            "rust:*.rs"
            "typescript:*.ts"
        )
        SERENA_MAX_ATTEMPTS=2
        ;;
    x86)
        BINARY_EXTENSIONS=("com" "exe" "asm")
        ;;
    snes)
        BINARY_EXTENSIONS=("com" "exe" "asm" "sfc" "smc")
        ;;
    68k)
        LANG_EXTENSIONS=(
            "asm:*.asm"
            "python:*.py"
            "go:*.go"
            "rust:*.rs"
            "typescript:*.ts"
        )
        SERENA_MAX_ATTEMPTS=2
        ;;
    image-dev)
        LANG_EXTENSIONS=(
            "python:*.py"
            "go:*.go"
            "rust:*.rs"
            "typescript:*.ts"
        )
        SERENA_MAX_ATTEMPTS=2
        ;;
    *)
        # Fallback: java-first detection matches pre-consolidation behavior.
        LANG_EXTENSIONS=(
            "java:*.java"
            "python:*.py"
            "go:*.go"
            "rust:*.rs"
            "typescript:*.ts"
        )
        SERENA_MAX_ATTEMPTS=3
        ;;
esac

echo "=== Initializing Workspace (Runtime Provisioning) ==="

# launch.sh pre-creates .claude, .serena, and .m2 on the host and bind-mounts
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
if [ ! -d "$HOME_DIR/.claude/.git" ]; then
    echo "Provisioning .claude config from remote..."
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
FIRST_LAUNCH_CLAUDE_JSON=false
if [ -f "$HOME_DIR/.claude.json" ]; then
    echo ".claude.json is bind-mounted -- consecutive launch."
else
    echo ".claude.json not present -- first launch. Will persist after session."
    FIRST_LAUNCH_CLAUDE_JSON=true
fi

# -------------------------------------------------------
# 5. Project Initialization Logic
#    LSP cold-start: Serena's 10s request timeout can be exceeded on first launch.
#    max_attempts is set per-variant above to match the expected warm-up time.
# -------------------------------------------------------
serena_index_with_retry() {
    local max_attempts=$SERENA_MAX_ATTEMPTS
    local attempt=1
    local delay=5

    while [ $attempt -le $max_attempts ]; do
        echo "  Indexing attempt $attempt of $max_attempts..."
        if serena project index 2>&1; then
            echo "  Indexing succeeded on attempt $attempt."
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            echo "  Indexing failed (LSP cold-start timeout). Retrying in ${delay}s..."
            sleep "$delay"
        fi
        attempt=$((attempt + 1))
    done

    echo "  Warning: Indexing failed after $max_attempts attempts."
    return 1
}

cd "$WORKSPACE_DIR"

# Binary-analysis variants (x86, snes) work on ROM/binary files; no Serena source project.
if [ ${#BINARY_EXTENSIONS[@]} -gt 0 ]; then
    echo "Binary analysis variant detected (VARIANT=${VARIANT:-unset})."

    if [ "${VARIANT}" = "snes" ]; then
        mkdir -p "${GHIDRA_PROJECTS_DIR:-/workspace/.ghidra-projects}"
        echo "  Ghidra projects directory: ${GHIDRA_PROJECTS_DIR:-/workspace/.ghidra-projects}"
    fi

    echo "  Detected binary extensions: ${BINARY_EXTENSIONS[*]}"
    echo "  Use Ghidra/radare2/ndisasm for analysis. No Serena project will be created."

    # MCP registration still applies for binary variants (Serena provides file tools).
    claude mcp add serena -- serena start-mcp-server --context ide-assistant --project /workspace >/dev/null 2>&1 || true

    if [ "$FIRST_LAUNCH_CLAUDE_JSON" = true ]; then
        persist_on_exit() {
            if [ -f "$HOME_DIR/.claude.json" ]; then
                cp "$HOME_DIR/.claude.json" "$PERSIST_DIR/.claude.json"
                echo "Persisted .claude.json for next launch."
            fi
        }
        trap persist_on_exit EXIT
    fi

    echo "=== Workspace Ready ==="
    echo ""
    echo "Start an interactive session with:"
    echo "  claude"
    echo ""

    if [ "$#" -gt 0 ]; then
        "$@"
    else
        bash
    fi
    exit 0
fi

# Check if this is the first time (no .serena directory in workspace)
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
        echo "Indexing project (with retry for LSP cold-start)..."
        serena_index_with_retry || echo "Warning: Failed to create project index"
    else
        echo "No source files detected. You can manually create the project with:"
        supported=""; for e in "${LANG_EXTENSIONS[@]}"; do supported="$supported ${e%%:*}"; done
        echo "  serena project create --language <lang> --index"
        echo "  Supported languages:$supported"
    fi
else
    echo "Project index found, updating (with retry for LSP cold-start)..."
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

claude mcp add serena -- serena start-mcp-server --context ide-assistant --project /workspace >/dev/null 2>&1 || true

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
