#!/bin/bash
set -e

if [ $# -eq 0 ]; then
    echo 'Usage: snes-analyze <rom.sfc|rom.smc> [analyzeHeadless options]'
    echo
    echo 'Imports and analyzes a SNES ROM with Ghidra headless using the 65816'
    echo 'processor and the SnesLoader extension. Disassembly is seeded from the'
    echo 'hardware vector table (RESET/NMI/IRQ/BRK/COP/ABORT) so auto-analysis has'
    echo 'real entry points to propagate from.'
    echo
    echo 'Environment overrides:'
    echo '  GHIDRA_PROJECTS_DIR   project location   (default /workspace/.ghidra-projects)'
    echo '  GHIDRA_SCRIPTS_DIR    Ghidra script path (default /opt/ghidra/Ghidra/Scripts)'
    echo '  SNES_SEED_ARGS        args to SeedSnesVectors.java: "<nativeMF> <nativeXF> <emu>"'
    echo '                        (default "1 1 0": native handlers 8-bit, RESET-only emu)'
    echo
    echo 'Extra analyzeHeadless options are passed through, e.g.:'
    echo '  snes-analyze game.sfc -postScript ExportDisasm.java'
    exit 1
fi

ROM="$1"
shift

PROJECTS_DIR="${GHIDRA_PROJECTS_DIR:-/workspace/.ghidra-projects}"
SCRIPTS_DIR="${GHIDRA_SCRIPTS_DIR:-/opt/ghidra/Ghidra/Scripts}"
SEED_ARGS="${SNES_SEED_ARGS:-1 1 0}"
PROJECT_NAME="$(basename "${ROM%.*}")_snes"

mkdir -p "$PROJECTS_DIR"

# NOTE: -loader takes the loader CLASS name (SnesLoader), not its display
# name ("SNES ROM"). The display name is only used in the GUI Import dialog.
exec analyzeHeadless \
    "$PROJECTS_DIR" "$PROJECT_NAME" \
    -import "$ROM" \
    -loader SnesLoader \
    -processor "65816:LE:16:default" \
    -cspec default \
    -scriptPath "$SCRIPTS_DIR" \
    -preScript SeedSnesVectors.java $SEED_ARGS \
    "$@"
