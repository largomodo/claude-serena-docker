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
MULTI_LANG=false

case "${VARIANT:-}" in
    # java-docker shares java's language detection; the rootless dockerd it
    # additionally needs is already started by the ENTRYPOINT wrapper
    # (start-dockerd.sh) before this script runs.
    java|java-docker)
        LANG_EXTENSIONS=(
            "java:*.java"
            "python:*.py"
            "go:*.go"
            "rust:*.rs"
            "typescript:*.ts"
        )
        SERENA_MAX_ATTEMPTS=3
        ;;
    # Fullstack variant: detects ALL languages present and creates one polyglot
    # Serena project (project.yml `languages` list, LSPs run in parallel), rather
    # than the first-match single-language detection used by other variants.
    # `angular` (detected via angular.json) subsumes typescript/html and Serena
    # docs forbid listing them together, so `angular` is listed before
    # `typescript` here so the subsumption rule (implemented below) can drop
    # typescript when both match. `python:*.py` is included because
    # Dockerfile.base ships Python system-wide and every other LSP-capable
    # variant arm already lists it for helper/automation scripts -- under
    # MULTI_LANG collect-all it only enters project.yml when .py files actually
    # exist, so it's free for pure Java+Angular projects. (ref: DL-011)
    java-angular)
        LANG_EXTENSIONS=(
            "java:*.java"
            "angular:angular.json"
            "typescript:*.ts"
            "python:*.py"
        )
        MULTI_LANG=true  # (ref: DL-007)
        # SERENA_MAX_ATTEMPTS=3 matches the java variant -- JDT-LS's 2G heap is
        # the binding cold-start constraint; the Angular LS first-use download
        # fits inside a smaller budget, comparable to clangd's, so 3 covers the
        # combined cold start. (ref: DL-012)
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
    # No Serena-supported Verilog LSP; Python covers helper/testbench scripts. (ref: DL-005)
    # SERENA_MAX_ATTEMPTS=2 matches other variants without cold-start-heavy LSPs.
    gowin)
        LANG_EXTENSIONS=("python:*.py")
        SERENA_MAX_ATTEMPTS=2
        ;;
    # KiCad files (.kicad_pcb/.kicad_sch) are s-expressions with no Serena LSP;
    # Python covers automation/helper scripts. KiCad MCP registered below. (ref: KI-001)
    kicad)
        LANG_EXTENSIONS=("python:*.py")
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

    if [ "$MULTI_LANG" = true ]; then
        # Collect every matching language (no first-match break) and create a
        # single polyglot project.
        # Scoped to MULTI_LANG=true so every other variant keeps first-match
        # behavior unchanged. (ref: DL-007)
        detected_langs=()
        for entry in "${LANG_EXTENSIONS[@]}"; do
            lang="${entry%%:*}"
            glob="${entry#*:}"
            if find . -maxdepth 12 -name "$glob" -type f | head -n 1 | grep -q .; then
                detected_langs+=("$lang")
            fi
        done

        # `angular` subsumes typescript/html; Serena docs forbid listing them together. (ref: DL-006)
        if printf '%s\n' "${detected_langs[@]}" | grep -qx "angular"; then
            filtered_langs=()
            for lang in "${detected_langs[@]}"; do
                [ "$lang" = "typescript" ] && continue
                filtered_langs+=("$lang")
            done
            detected_langs=("${filtered_langs[@]}")
        fi

        if [ ${#detected_langs[@]} -gt 0 ]; then
            echo "Detected languages:${detected_langs[*]/#/ }, creating polyglot project..."
            lang_args=()
            for lang in "${detected_langs[@]}"; do
                lang_args+=(--language "$lang")
            done
            serena project create "${lang_args[@]}" || echo "Warning: Failed to create project"
            echo "Indexing project (with retry for LSP cold-start)..."
            serena_index_with_retry || echo "Warning: Failed to create project index"

            # Angular LS silently degrades (template-aware features return empty
            # results, no error) until npm install has run in the project root.
            # This script never runs npm ci on the user's project -- surface the
            # cause instead so degraded Serena tools aren't misread as breakage. (ref: DL-008)
            if printf '%s\n' "${detected_langs[@]}" | grep -qx "angular"; then
                angular_json=$(find . -maxdepth 12 -name "angular.json" -type f | head -n 1)
                if [ -n "$angular_json" ]; then
                    angular_dir=$(dirname "$angular_json")
                    if [ ! -d "$angular_dir/node_modules" ]; then
                        echo "Warning: Angular project detected at $angular_json but no node_modules found."
                        echo "  Angular LS template-aware features will stay degraded until 'npm ci' is run in $angular_dir."
                        echo "  This script does not run it for you."
                    fi
                fi
            fi
        else
            echo "No source files detected. You can manually create the project with:"
            supported=""; for e in "${LANG_EXTENSIONS[@]}"; do supported="$supported ${e%%:*}"; done
            echo "  serena project create --language <lang> --index"
            echo "  Supported languages:$supported"
        fi
    else
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

# KiCad MCP: Node front-end (dist/index.js) spawns the venv Python backend.
# KICAD_PYTHON points the Node layer at the --system-site-packages venv, which has
# both the MCP's deps and the system pcbnew bindings; KICAD_BACKEND=swig forces the
# file-based backend (headless KiCad 9 has no running GUI for IPC). (ref: KI-001)
# FREEROUTING_JAR points the autorouter at the baked /opt jar instead of its default
# ~/.kicad-mcp/freerouting.jar (passed explicitly here too, mirroring KICAD_BACKEND). (ref: KI-008)
if [ "${VARIANT:-}" = "kicad" ]; then
    echo "Registering KiCad MCP server..."
    claude mcp add kicad \
        -e KICAD_PYTHON=/opt/kicad-mcp/.venv/bin/python \
        -e KICAD_BACKEND=swig \
        -e FREEROUTING_JAR=/opt/freerouting/freerouting.jar \
        -- node /opt/kicad-mcp/dist/index.js >/dev/null 2>&1 || true
fi

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
