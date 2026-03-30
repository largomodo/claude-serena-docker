#!/bin/bash
# Dockerfile COPY and chmod follow the same pattern as dis16/r216/dump16. (DL-007)
set -e  # Exit immediately if analyzeHeadless fails; caller receives non-zero status

if [ $# -eq 0 ]; then
    echo 'Usage: snes-analyze <rom.sfc|rom.smc> [analyzeHeadless options]'
    echo 'Imports and analyzes a SNES ROM using Ghidra headless with the 65816 processor.'
    exit 1
fi

ROM="$1"
shift

# Fallback defaults match Dockerfile ENV values; functional when invoked
# via docker exec before init-workspace.sh runs (DL-006, DL-007)
PROJECTS_DIR="${GHIDRA_PROJECTS_DIR:-/workspace/.ghidra-projects}"
SCRIPTS_DIR="${GHIDRA_SCRIPTS_DIR:-/opt/ghidra/Ghidra/Scripts}"
PROJECT_NAME="$(basename "${ROM%.*}")_snes"

# Defensive mkdir: init-workspace.sh also creates this directory, but
# snes-analyze may be invoked directly via docker exec before init runs.
# Both sites create the directory to cover each workflow independently. (DL-006)
mkdir -p "$PROJECTS_DIR"

# exec replaces this shell process so analyzeHeadless receives signals directly
# and the exit code propagates without wrapping. (DL-007)
exec analyzeHeadless \
    "$PROJECTS_DIR" "$PROJECT_NAME" \
    -import "$ROM" \
    -loader "SNES ROM" \
    -processor "65816:LE:16:default" \
    -cspec default \
    -scriptPath "$SCRIPTS_DIR" \
    -postScript SetSnesRegisters.java \
    "$@"
