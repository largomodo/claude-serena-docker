#!/bin/bash
set -e

# Failure policy, two tiers:
#   Fatal (exit 1): files the image must deliver (claude-env.md tool sheet,
#   serena_config.yml template) and the first claude-config clone. A shell
#   without them misrepresents the image.
#   Warn (warn(), shell still starts): Serena project creation and indexing,
#   MCP registration, config refresh (git pull), the mv of cloned config
#   contents into place after the fatal clone, and the rmdir of the empty
#   .serena directory.
# `|| true` appears only on `claude mcp remove serena`: no registration yet is
# the normal first-run case. The expected-non-event `rmdir .serena` uses
# --ignore-fail-on-non-empty rather than a tolerance operator, so a real rmdir
# error still reaches warn().

# Configuration Constants
WORKSPACE_DIR="/workspace"
PERSIST_DIR="/workspace/.claudeproject"
TEMPLATE_DIR="/usr/local/share/claude-env"
HOME_DIR="/home/codeuser"
CLAUDE_CONFIG_REPO="https://github.com/largomodo/claude-config.git"

# Non-fatal diagnostics share one stderr prefix so a degraded step stands out
# from normal progress output. Returns 0 so a degraded step never aborts the
# shell under set -e.
warn() { echo "  Warning: $*" >&2; }

# VARIANT env var is set by the variant Dockerfile (e.g., ENV VARIANT=java).
# Defaults and arrays are set in the case block below; shared logic uses them after.
# LANG_GLOBS: ordered "language:glob" pairs; order is detection priority, so
# an earlier language wins when several are present.
LANG_GLOBS=()
BINARY_EXTENSIONS=()
SERENA_MAX_ATTEMPTS=3
# MULTI_LANG: true collects every matching language into one polyglot Serena
# project; false stops at the first match (single-language projects index faster).
MULTI_LANG=false
# CREATE_GHIDRA_PROJECTS_DIR: Ghidra variants need a persisted project dir on
# the bind mount; other variants must not leave an unused directory behind.
CREATE_GHIDRA_PROJECTS_DIR=false
# REGISTER_KICAD_MCP: the KiCad MCP server exists only in the kicad image, so
# registration is gated rather than attempted (and failing) elsewhere.
REGISTER_KICAD_MCP=false

# Single variant dispatch point: every per-variant behavior is set here; the
# shared logic below branches on these variables, never on VARIANT itself.
case "${VARIANT:-}" in
    # java-docker shares java's language detection; the rootless dockerd it
    # additionally needs is already started by the ENTRYPOINT wrapper
    # (start-dockerd.sh) before this script runs.
    java|java-docker)
        LANG_GLOBS=(
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
        LANG_GLOBS=(
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
    # arduino shares clangd detection; `.ino` is not a clangd extension, so an
    # .ino-only sketch reports no source files and the compile-database
    # recipe in arduino-notes.md is the manual step. (ref: DL-009 in
    # plan-arduino-nano.md)
    c|c-pico|arduino)
        # clangd is baked (apt) and referenced by ls_path, so 2 attempts cover indexing alone.
        LANG_GLOBS=(
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
        # Ghidra projects persist under /workspace/.ghidra-projects
        # (GHIDRA_PROJECTS_DIR overrides the location).
        CREATE_GHIDRA_PROJECTS_DIR=true
        ;;
    68k)
        # Serena has no assembler language id, so .asm sources are not indexed;
        # the array covers the helper and build scripts in the project.
        LANG_GLOBS=(
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
        LANG_GLOBS=("python:*.py")
        SERENA_MAX_ATTEMPTS=2
        ;;
    # KiCad files (.kicad_pcb/.kicad_sch) are s-expressions with no Serena LSP;
    # Python covers automation/helper scripts. KiCad MCP registered via REGISTER_KICAD_MCP below. (ref: KI-001)
    kicad)
        LANG_GLOBS=("python:*.py")
        SERENA_MAX_ATTEMPTS=2
        REGISTER_KICAD_MCP=true
        ;;
    image-dev)
        LANG_GLOBS=(
            "python:*.py"
            "go:*.go"
            "rust:*.rs"
            "typescript:*.ts"
        )
        SERENA_MAX_ATTEMPTS=2
        ;;
    *)
        # Fallback for unknown or unset VARIANT: java first, then python, go, rust, typescript.
        LANG_GLOBS=(
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
# launch.sh pre-creates $PERSIST_DIR, so the directory exists before this
# script runs; the gitignore is keyed on its own absence.
mkdir -p "$PERSIST_DIR"
if [ ! -f "$PERSIST_DIR/.gitignore" ]; then
    echo '*' > "$PERSIST_DIR/.gitignore"
fi

# 2. Provisioning

# 2a. Claude Config (Git-based)
if [ ! -d "$HOME_DIR/.claude/.git" ]; then
    echo "Provisioning .claude config from remote..."
    TMPCLONE=$(mktemp -d)
    if git clone --depth 1 "$CLAUDE_CONFIG_REPO" "$TMPCLONE"; then
        shopt -s dotglob
        if mv "$TMPCLONE"/* "$HOME_DIR/.claude/"; then
            echo "  Successfully cloned claude-config."
        else
            warn "claude-config cloned but some files could not be moved into ~/.claude (pre-populated directory?) -- see errors above"
        fi
        shopt -u dotglob
        rm -rf "$TMPCLONE"
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
        warn "Failed to update .claude config (network issue or conflict)."
    fi
fi

# 2a'. Container tool sheet
# Runs on every launch, before the binary-variant early exit below, so x86
# and snes receive it too. Unconditional cp because .claudeproject/.claude
# persists across image rebuilds -- a first-launch-only copy would go stale
# once the image ships an updated sheet. Missing sheet is fatal: it is a
# baked artifact every variant Dockerfile must produce via its concat+check
# RUN, and a silent start without it would defeat deterministic delivery.
# The file stays untracked in the claude-config checkout, so the
# `git pull --rebase` in section 2a never conflicts with it.
if [ -f "$TEMPLATE_DIR/claude-env.md" ]; then
    cp "$TEMPLATE_DIR/claude-env.md" "$HOME_DIR/.claude/claude-env.md"
    echo "  Installed container tool sheet."
else
    echo "  Error: container tool sheet not found in $TEMPLATE_DIR -- image was built without the concat+check step; rebuild with ./build.sh <tag> $VARIANT"
    exit 1
fi

# 2b. Serena Config (Template-based)
# ~/.serena persists across image rebuilds, so the template is copied on
# every launch (same pattern as the claude-env.md copy in 2a). Serena re-adds
# the /workspace project entry from --project on every start and regenerates
# auth_secret, so nothing runtime-written is lost; dashboard edits do not
# persist.
echo "Provisioning Serena configuration from image..."
if [ -f "$TEMPLATE_DIR/serena_config.yml" ]; then
    cp "$TEMPLATE_DIR/serena_config.yml" "$HOME_DIR/.serena/serena_config.yml"
    echo "  Installed Serena configuration from image."
else
    echo "  Error: Master serena_config.yml not found in $TEMPLATE_DIR"
    exit 1
fi

# 3. Handle .claude.json
# launch.sh decides first vs consecutive launch (.claude.json present with
# hasCompletedOnboarding true) and passes the verdict as CLAUDE_JSON_MOUNTED.
# This script never inspects ~/.claude.json itself. launch.sh decides because
# the onboarding marker guards against a half-written .claude.json: a file
# present but without hasCompletedOnboarding must not be treated as mounted.
# An absent variable (bare docker run) means first launch, so the file is still
# persisted on exit. The rejected alternative is failing fast on an unset
# variable; persisting is harmless on a consecutive launch and never loses auth.
# (ref: DL-012 in plan-refactor-improvement-work-items.md)
if [ "${CLAUDE_JSON_MOUNTED:-false}" = true ]; then
    echo ".claude.json is bind-mounted -- consecutive launch."
else
    echo ".claude.json not mounted -- first launch. Will persist after session."
    persist_on_exit() {
        if [ -f "$HOME_DIR/.claude.json" ]; then
            cp "$HOME_DIR/.claude.json" "$PERSIST_DIR/.claude.json"
            echo "Persisted .claude.json for next launch."
        fi
    }
    # Armed on first launch only: on later launches the file is bind-mounted,
    # so the host copy is already live. An unset CLAUDE_JSON_MOUNTED lands here
    # too: a container started without launch.sh has no mount, so the trap is
    # what keeps the file from being lost on exit.
    trap persist_on_exit EXIT
fi

# -------------------------------------------------------
# 5. Project Initialization Logic
#    LSP cold-start: Serena's 10s request timeout can be exceeded on first launch.
#    max_attempts is set per-variant above to match the expected warm-up time.
# -------------------------------------------------------
# Serena's `project index` hard-codes <root>/.serena/logs/indexing.txt for
# failed files, ignoring the configured project folder location (serena
# cli.py `project index` log_file, v2.0.0). Move those logs under
# .claudeproject/serena so no stray .serena is left in the repo. Becomes
# redundant once upstream derives log_file from the project folder location.
relocate_serena_index_logs() {
    if [ ! -f .serena/project.yml ] && [ -d .serena/logs ]; then
        mkdir -p .claudeproject/serena
        mv .serena/logs .claudeproject/serena/ || warn "could not move .serena/logs under .claudeproject/serena"
        # A .serena that still holds other content is the designed outcome
        # (exit 0 via the flag), so only a real rmdir failure warns.
        rmdir --ignore-fail-on-non-empty .serena || warn "could not remove .serena"
    fi
}

# `claude mcp add` refuses with already-exists and keeps the registered
# command, and the registration lives in the persisted .claude.json.
# Remove-then-add converges the command on every launch; the remove fails
# harmlessly when no registration exists.
register_serena_mcp() {
    claude mcp remove serena >/dev/null 2>&1 || true
    claude mcp add serena -- serena start-mcp-server --context claude-code --project /workspace >/dev/null 2>&1 \
        || warn "Serena MCP registration failed -- re-register with the commands printed at Workspace Ready"
}

# Fills DETECTED_LANGS from LANG_GLOBS (entries "<lang>:<glob>"). Stops at the
# first match unless MULTI_LANG=true (java-angular), which collects every
# language so one polyglot project is created. (ref: DL-010, DL-011 in plan-refactor-improvement-work-items.md)
# One loop serves both modes: collect-all and first-match differ only in the
# break, so the single-language case is the one-element case of the polyglot
# one. The caller keeps separate log wording per mode.
detect_languages() {
    local entry lang glob
    DETECTED_LANGS=()
    # Result goes to a global array: bash functions cannot return arrays.
    for entry in "${LANG_GLOBS[@]}"; do
        lang="${entry%%:*}"
        glob="${entry#*:}"
        if find . -maxdepth 12 -name "$glob" -type f | head -n 1 | grep -q .; then
            DETECTED_LANGS+=("$lang")
            [ "$MULTI_LANG" = true ] || break
        fi
    done
}

serena_index_with_retry() {
    local max_attempts=$SERENA_MAX_ATTEMPTS
    local attempt=1
    local delay=5

    while [ $attempt -le $max_attempts ]; do
        echo "  Indexing attempt $attempt of $max_attempts..."
        if serena project index 2>&1; then
            relocate_serena_index_logs
            echo "  Indexing succeeded on attempt $attempt."
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            echo "  Indexing failed (LSP cold-start timeout). Retrying in ${delay}s..."
            sleep "$delay"
        fi
        attempt=$((attempt + 1))
    done

    relocate_serena_index_logs
    warn "Indexing failed after $max_attempts attempts."
    return 1
}

cd "$WORKSPACE_DIR"

# Binary-analysis variants (x86, snes) work on ROM/binary files; no Serena source project.
if [ ${#BINARY_EXTENSIONS[@]} -gt 0 ]; then
    echo "Binary analysis variant detected (VARIANT=${VARIANT:-unset})."

    # Flag comes from the variant case table, which keeps variant names out of
    # the shared flow.
    if [ "$CREATE_GHIDRA_PROJECTS_DIR" = true ]; then
        mkdir -p "${GHIDRA_PROJECTS_DIR:-/workspace/.ghidra-projects}"
        echo "  Ghidra projects directory: ${GHIDRA_PROJECTS_DIR:-/workspace/.ghidra-projects}"
    fi

    echo "  Detected binary extensions: ${BINARY_EXTENSIONS[*]}"
    echo "  Use Ghidra/radare2/ndisasm for analysis. No Serena project will be created."

    # MCP registration still applies for binary variants (Serena provides file tools).
    register_serena_mcp

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

# Project-creation gate. The configured Serena folder is
# .claudeproject/serena; a project that has a .serena folder uses that one,
# and re-running `serena project create` on either would fail with
# FileExistsError.
if [ ! -f ".claudeproject/serena/project.yml" ] && [ ! -f ".serena/project.yml" ]; then
    echo "Checking for project initialization..."

    detect_languages

    # `angular` subsumes typescript/html; Serena docs forbid listing them together. (ref: DL-006)
    if printf '%s\n' "${DETECTED_LANGS[@]}" | grep -qx "angular"; then
        filtered_langs=()
        for lang in "${DETECTED_LANGS[@]}"; do
            [ "$lang" = "typescript" ] && continue
            filtered_langs+=("$lang")
        done
        DETECTED_LANGS=("${filtered_langs[@]}")
    fi

    if [ ${#DETECTED_LANGS[@]} -gt 0 ]; then
        if [ "$MULTI_LANG" = true ]; then
            echo "Detected languages: ${DETECTED_LANGS[*]}, creating polyglot project..."
        else
            echo "${DETECTED_LANGS[0]} source files detected, creating ${DETECTED_LANGS[0]} project..."
        fi
        lang_args=()
        for lang in "${DETECTED_LANGS[@]}"; do
            lang_args+=(--language "$lang")
        done
        serena project create "${lang_args[@]}" || warn "Failed to create project"
        echo "Indexing project (with retry for LSP cold-start)..."
        serena_index_with_retry || warn "Failed to create project index"

        # Angular LS silently degrades (template-aware features return empty
        # results, no error) until npm install has run in the project root.
        # This script never runs npm ci on the user's project -- surface the
        # cause instead so degraded Serena tools aren't misread as breakage. (ref: DL-008)
        if printf '%s\n' "${DETECTED_LANGS[@]}" | grep -qx "angular"; then
            angular_json=$(find . -maxdepth 12 -name "angular.json" -type f | head -n 1)
            if [ -n "$angular_json" ]; then
                angular_dir=$(dirname "$angular_json")
                if [ ! -d "$angular_dir/node_modules" ]; then
                    warn "Angular project detected at $angular_json but no node_modules found."
                    echo "  Angular LS template-aware features will stay degraded until 'npm ci' is run in $angular_dir."
                    echo "  This script does not run it for you."
                fi
            fi
        fi
    else
        echo "No source files detected. You can manually create the project with:"
        supported=""; for e in "${LANG_GLOBS[@]}"; do supported="$supported ${e%%:*}"; done
        echo "  serena project create --language <lang> --index"
        echo "  Supported languages:$supported"
    fi
else
    echo "Project index found, updating (with retry for LSP cold-start)..."
    serena_index_with_retry || warn "Failed to update index"
fi

echo "=== Workspace Ready ==="
echo ""
echo "Serena is registered automatically. To re-register manually, run:"
echo "  claude mcp remove serena"
echo "  claude mcp add serena -- serena start-mcp-server --context claude-code --project /workspace"
echo ""
echo "Or start an interactive session with:"
echo "  claude"
echo ""

register_serena_mcp

# KiCad MCP: Node front-end (dist/index.js) spawns the venv Python backend.
# KICAD_PYTHON points the Node layer at the --system-site-packages venv, which has
# both the MCP's deps and the system pcbnew bindings; KICAD_BACKEND=swig forces the
# file-based backend (headless KiCad 9 has no running GUI for IPC). (ref: KI-001)
# FREEROUTING_JAR points the autorouter at the baked /opt jar instead of its default
# ~/.kicad-mcp/freerouting.jar (passed explicitly here too, mirroring KICAD_BACKEND). (ref: KI-008)
# A repeated `claude mcp add kicad` fails with already-exists and keeps the
# registered command; the registration persists in .claude.json. When this
# command line changes, precede it with `claude mcp remove kicad >/dev/null 2>&1 || true`
# so existing workspaces pick up the new command.
# REGISTER_KICAD_MCP comes from the variant case table, the single dispatch
# point, which keeps variant names out of the shared flow.
if [ "$REGISTER_KICAD_MCP" = true ]; then
    echo "Registering KiCad MCP server..."
    claude mcp add kicad \
        -e KICAD_PYTHON=/opt/kicad-mcp/.venv/bin/python \
        -e KICAD_BACKEND=swig \
        -e FREEROUTING_JAR=/opt/freerouting/freerouting.jar \
        -- node /opt/kicad-mcp/dist/index.js >/dev/null 2>&1 || warn "KiCad MCP registration failed"
fi

if [ "$#" -gt 0 ]; then
    "$@"
else
    bash
fi
