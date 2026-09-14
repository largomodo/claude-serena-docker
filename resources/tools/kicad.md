# claude-env container toolchain: kicad

## Tools (kicad)

| Tool | What | Use when |
| --- | --- | --- |
| `kicad-cli` | Export/DRC/ERC/plot | Export, check, or plot a design |
| `freeroute` | Headless freerouting | Autorouting a single DSN/SES pair |
| `kicad-autoroute` | Wraps freeroute: export, route, reimport | One-command autorouting of a .kicad_pcb |
| `java` | JDK 25 for freerouting | Debugging a freerouting launch failure |

## Environment (kicad)

| Variable | What |
| --- | --- |
| `VARIANT` | Container variant name (`kicad`) |
| `JAVA_HOME` | JDK installation root |
| `KICAD_BACKEND` | Forces the file-based SWIG backend |
| `FREEROUTING_JAR` | Baked freerouting jar path |
| `QT_QPA_PLATFORM` | Forces offscreen Qt rendering |

## MCP servers (kicad)

| Server | What |
| --- | --- |
| `kicad` | `node /opt/kicad-mcp/dist/index.js`; SWIG backend |

## Notes (kicad)

- `pcbnew` imports only from /opt/kicad-mcp/.venv/bin/python, not `python`.
- No Specctra subcommand in kicad-cli 9; use `kicad-autoroute` or kicad_specctra.py.
- No display; the IPC backend is unavailable.
- Read /usr/local/share/claude-env/tools/kicad-notes.md for autorouting, scripting pcbnew, or a pcbnew import error.
- Presence on PATH is what the build verifies; it does not guarantee a tool succeeds for every invocation.
