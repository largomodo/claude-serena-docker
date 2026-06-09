#!/bin/bash
# kicad-autoroute -- one-command headless autoroute of a KiCad board with freerouting.
#
#   export DSN (pcbnew SWIG) -> freerouting -> import SES (pcbnew SWIG) -> save board
#
# Usage: kicad-autoroute <board.kicad_pcb> [max_passes]
#
# Writes <board>.dsn, <board>.ses and <board>-routed.kicad_pcb beside the input.
# The original board is never modified; routed copper lands in the -routed copy.
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: kicad-autoroute <board.kicad_pcb> [max_passes]" >&2
    exit 2
fi

BOARD="$1"
PASSES="${2:-100}"

if [ ! -f "$BOARD" ]; then
    echo "kicad-autoroute: board not found: $BOARD" >&2
    exit 1
fi

base="${BOARD%.kicad_pcb}"
DSN="${base}.dsn"
SES="${base}.ses"
ROUTED="${base}-routed.kicad_pcb"

# pcbnew lives in the MCP venv (--system-site-packages); the cli-tools venv that
# owns `python` on PATH cannot see it, so call the MCP interpreter directly. (ref: KI-001)
PCBNEW_PY=/opt/kicad-mcp/.venv/bin/python
HELPER=/usr/local/lib/kicad-tools/kicad_specctra.py

echo "[1/3] Exporting Specctra DSN -> $DSN"
"$PCBNEW_PY" "$HELPER" export "$BOARD" "$DSN"

echo "[2/3] Autorouting with freerouting (${PASSES} passes) -> $SES"
freeroute "$DSN" "$SES" "$PASSES"

if [ ! -f "$SES" ]; then
    echo "kicad-autoroute: freerouting did not produce $SES" >&2
    exit 1
fi

echo "[3/3] Importing routed session -> $ROUTED"
"$PCBNEW_PY" "$HELPER" import "$BOARD" "$SES" "$ROUTED"

echo "Done. Routed board: $ROUTED"
