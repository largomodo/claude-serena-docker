#!/bin/bash
# freeroute -- headless freerouting wrapper: autoroute a Specctra .dsn into a .ses.
#
# Usage: freeroute <input.dsn> <output.ses> [max_passes] [extra freerouting args...]
#
# Thin wrapper around /opt/freerouting/freerouting.jar. -Djava.awt.headless=true is
# mandatory: freerouting touches AWT geometry even with no GUI window (ref: KI-006).
set -euo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: freeroute <input.dsn> <output.ses> [max_passes] [extra args...]" >&2
    exit 2
fi

IN="$1"
OUT="$2"
PASSES="${3:-100}"

if [ ! -f "$IN" ]; then
    echo "freeroute: input DSN not found: $IN" >&2
    exit 1
fi

# -de design-in, -do design-out, -mp max-passes (classic CLI, retained in 2.x).
exec java -Djava.awt.headless=true \
    -jar /opt/freerouting/freerouting.jar \
    -de "$IN" -do "$OUT" -mp "$PASSES" "${@:4}"
