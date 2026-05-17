#!/bin/bash
set -e

if [ $# -eq 0 ]; then
    echo 'Usage: snes-analyze <rom.sfc|rom.smc> [analyzeHeadless options]'
    echo 'Imports and analyzes a SNES ROM using Ghidra headless with the 65816 processor.'
    exit 1
fi

ROM="$1"
shift

PROJECTS_DIR="${GHIDRA_PROJECTS_DIR:-/workspace/.ghidra-projects}"
SCRIPTS_DIR="${GHIDRA_SCRIPTS_DIR:-/opt/ghidra/Ghidra/Scripts}"
PROJECT_NAME="$(basename "${ROM%.*}")_snes"

mkdir -p "$PROJECTS_DIR"

exec analyzeHeadless \
    "$PROJECTS_DIR" "$PROJECT_NAME" \
    -import "$ROM" \
    -loader "SNES ROM" \
    -processor "65816:LE:16:default" \
    -cspec default \
    -scriptPath "$SCRIPTS_DIR" \
    -postScript SetSnesRegisters.java \
    "$@"
