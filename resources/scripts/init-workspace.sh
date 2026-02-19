#!/bin/bash
set -e

# Configuration Constants
WORKSPACE_DIR="/workspace"
PERSIST_DIR="/workspace/.claudeproject"
TEMPLATE_DIR="/usr/local/share/claude-env"
HOME_DIR="/home/codeuser"
CLAUDE_CONFIG_REPO="https://github.com/largomodo/claude-config.git"

echo "=== Initializing Workspace (Runtime Provisioning) ==="

# 1. Setup Persistence Root
if [ ! -d "$PERSIST_DIR" ]; then
    echo "Creating persistence directory..."
    mkdir -p "$PERSIST_DIR"
    echo '*' > "$PERSIST_DIR/.gitignore"
fi

# 2. Provisioning Functions

# Provision Claude Config (Git based)
provision_claude_config() {
    local target="$PERSIST_DIR/.claude"
    local symlink="$HOME_DIR/.claude"

    if [ ! -d "$target" ]; then
        echo "Provisioning .claude config from remote..."
        # Clone directly to persistence
        if git clone --depth 1 "$CLAUDE_CONFIG_REPO" "$target"; then
            echo "  Successfully cloned claude-config."
        else
            echo "  Error: Failed to clone claude-config."
            return 1
        fi
    else
        echo "Refreshing .claude config..."
        # Attempt pull, but don't fail boot if network is down or conflicts exist
        if (cd "$target" && git pull --rebase); then
            echo "  Config updated."
        else
            echo "  Warning: Failed to update .claude config (network issue or conflict)."
        fi
    fi
    
    # Symlink to home
    ln -sfn "$target" "$symlink"
    echo "  Symlinked .claude -> $target"
}

# Provision Serena Config (Template + Patch based)
provision_serena_config() {
    local target_dir="$PERSIST_DIR/.serena"
    local target_file="$target_dir/serena_config.yml"
    local symlink="$HOME_DIR/.serena"
    
    if [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir"
    fi

    if [ ! -f "$target_file" ]; then
        echo "Provisioning Serena configuration from image..."
        if [ -f "$TEMPLATE_DIR/serena_config.yml" ]; then
            cp "$TEMPLATE_DIR/serena_config.yml" "$target_file"
            echo "  Copied serena_config.yml."
        else
            echo "  Error: Master serena_config.yml not found in $TEMPLATE_DIR"
            return 1
        fi
    fi

    # Symlink to home
    ln -sfn "$target_dir" "$symlink"
    echo "  Symlinked .serena -> $target_dir"
}

# Provision Maven (.m2) for Java persistence
provision_m2() {
    local target="$PERSIST_DIR/.m2"
    local symlink="$HOME_DIR/.m2"
    
    if [ ! -d "$target" ]; then
        mkdir -p "$target"
    fi
    
    ln -sfn "$target" "$symlink"
}

# 3. Execute Provisioning
provision_claude_config
provision_serena_config
provision_m2

# 4. Handle .claude.json (Auth token)
# This file is often created by the tool at runtime. We want to persist it if it exists.
link_auth_file() {
    local persist_file="$PERSIST_DIR/.claude.json"
    local home_file="$HOME_DIR/.claude.json"

    # If user manually logged in (file exists in home but not symlink), move to persist
    if [ -f "$home_file" ] && [ ! -L "$home_file" ]; then
        echo "Detected existing auth token. Moving to persistence..."
        mv "$home_file" "$persist_file"
    fi
    
    # If persistence exists, ensure it is linked
    if [ -f "$persist_file" ]; then
        ln -sf "$persist_file" "$home_file"
        echo "  Symlinked .claude.json auth token."
    fi
}
link_auth_file

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
    
    # Detect if there are any source files to determine language
    if find . -maxdepth 12 -name "*.java" -type f | head -n 1 | grep -q .; then
        echo "Java source files detected, creating Java project..."
        serena project create --language java || echo "Warning: Failed to create project"
        echo "Indexing project (with retry for jdtls cold-start)..."
        serena_index_with_retry || echo "Warning: Failed to create project index"
    else
        echo "No source files detected. You can manually create the project with:"
        echo "  serena project create --language java --index"
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

# Re-check auth file link in case the MCP command created a new file
link_auth_file

# If other commands were passed to `docker run`, execute them.
# Otherwise, default to starting an interactive bash shell.
if [ "$#" -gt 0 ]; then
    exec "$@"
else
    exec bash
fi
