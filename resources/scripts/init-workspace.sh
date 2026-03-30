#!/bin/bash
set -e

# Configuration Constants
WORKSPACE_DIR="/workspace"
PERSIST_DIR="/workspace/.claudeproject"
TEMPLATE_DIR="/usr/local/share/claude-env"
HOME_DIR="/home/codeuser"
CLAUDE_CONFIG_REPO="https://github.com/largomodo/claude-config.git"

BINARY_EXTENSIONS=(
    "com:*.com"
    "exe:*.exe"
    "asm:*.asm"
    # SNES ROM extensions; detected separately from x86 types to provide
    # architecture-specific tool recommendations. (DL-008)
    "sfc:*.sfc"
    "smc:*.smc"
)

echo "=== Initializing Workspace (Runtime Provisioning) ==="

# launch.sh pre-creates .claude and .serena on the host and bind-mounts
# them before container start. (DL-004, DL-006)

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
# reliable marker that the clone has been completed. (DL-005)
if [ ! -d "$HOME_DIR/.claude/.git" ]; then
    echo "Provisioning .claude config from remote..."
    # git clone refuses non-empty directories; bind mounts create . and ..
    # entries making the target non-empty. Clone to a temp dir then move
    # contents into the mount point. shopt dotglob ensures hidden files
    # (including .git) are transferred. (DL-003, R-005)
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
# persists to the host filesystem without a separate copy step. (DL-004, DL-006)
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
# its onboarding flow, so the check guards against premature mounting. (DL-002)
#
# On first launch, FIRST_LAUNCH_CLAUDE_JSON is set to true. After the interactive
# session ends, an EXIT trap copies ~/.claude.json (created by Claude Code during
# onboarding) to $PERSIST_DIR/.claude.json. The next launch will bind-mount it.
# (DL-001, DL-002)
FIRST_LAUNCH_CLAUDE_JSON=false
if [ -f "$HOME_DIR/.claude.json" ]; then
    echo ".claude.json is bind-mounted -- consecutive launch."
else
    echo ".claude.json not present -- first launch. Will persist after session."
    FIRST_LAUNCH_CLAUDE_JSON=true
fi

cd "$WORKSPACE_DIR"

# mkdir -p guards against the case where init-workspace runs before snes-analyze.sh
# is invoked; snes-analyze.sh also calls mkdir -p for direct docker-exec workflows. (DL-006)
mkdir -p "${GHIDRA_PROJECTS_DIR:-/workspace/.ghidra-projects}"

echo "Checking for binary files..."
detected_types=""
for entry in "${BINARY_EXTENSIONS[@]}"; do
    ext="${entry%%:*}"
    glob="${entry#*:}"
    if find . -maxdepth 12 -name "$glob" -type f | head -n 1 | grep -q .; then
        detected_types="$detected_types $ext"
    fi
done
if [ -n "$detected_types" ]; then
    echo "Binary file types detected:$detected_types"
    # Categorize detected types by architecture to provide tool-specific
    # recommendations; x86 and SNES require different Ghidra processor
    # strings and different wrappers. (DL-008)
    x86_detected=""
    snes_detected=""
    for t in $detected_types; do
        case "$t" in
            com|exe|asm) x86_detected="$x86_detected $t" ;;
            sfc|smc)     snes_detected="$snes_detected $t" ;;
        esac
    done
    if [ -n "$x86_detected" ]; then
        echo "x86 DOS binaries ($x86_detected): use dis16, r216, dump16, or analyzeHeadless -processor x86:LE:16:Real Mode:default"
    fi
    if [ -n "$snes_detected" ]; then
        echo "SNES ROMs ($snes_detected): use snes-analyze, or analyzeHeadless -processor 65816:LE:16:default"
    fi
else
    echo "No .com/.exe/.asm/.sfc/.smc files detected in workspace."
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
# bind-mount the persisted file. (DL-001)
#
# exec would replace this shell process, making traps registered here unreachable.
# Foreground bash (without exec) preserves this shell so the EXIT trap fires
# when the user exits the session. (DL-001, RA-001)
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
