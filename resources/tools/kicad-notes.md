# kicad notes

Condensed from README.md Troubleshooting > kicad; edit both. Also
condensed from Dockerfile.kicad decision comments.

Backend reality: only the SWIG file-based backend (`import pcbnew`) works
headless. KiCad 9's IPC backend (`kipy`) needs a running GUI and has no
plot/export, so `KICAD_BACKEND=swig` is forced.

Autoroute pipeline (`kicad-autoroute`): exports `.dsn`, routes it with
`freeroute` into `.ses`, imports the result into a `-routed.kicad_pcb`
copy; the original file is never touched. Call
`kicad_specctra.py export`/`import` directly with the MCP venv interpreter
(/opt/kicad-mcp/.venv/bin/python) for a single stage.

freerouting needs Java 25 and `-Djava.awt.headless=true` (the `freeroute`
wrapper sets this); `FREEROUTING_JAR` overrides the jar path.

If the kicad MCP tools vanish, re-register manually:
```
claude mcp add kicad \
  -e KICAD_PYTHON=/opt/kicad-mcp/.venv/bin/python \
  -e KICAD_BACKEND=swig \
  -e FREEROUTING_JAR=/opt/freerouting/freerouting.jar \
  -- node /opt/kicad-mcp/dist/index.js
```

Symbol and footprint libraries are installed (`--install-recommends`).

This file is prose only: check-tools.sh verifies the sheet's `## Tools` and `## Environment` tables, never the content here.
