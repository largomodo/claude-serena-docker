# REA notes (x86, 68k, android)

Mirrors the `x86 / 68k / android:` Troubleshooting subsections in README.md; edit both.

REA (github.com/morluto/rea, npm `rea-agents`) is the MCP server `rea` and
the `rea` CLI. Its native analysis engine is the baked Ghidra at
`$GHIDRA_INSTALL_DIR` (/opt/ghidra). In x86 and 68k it is the only engine:
Hopper, IDA, JADX, Frida and browser targets are not installed and their
tools report unavailable. The android variant adds the JADX, Apktool, adb,
Frida and mitmdump providers (see android-notes.md); Hopper, IDA and browser
targets stay unavailable there too. Every session
imports the target into a private, read-only, ephemeral Ghidra project:
nothing is written under /workspace or /workspace/.ghidra-projects, name
and comment edits (`annotate_native_function`) vanish on `close_binary`, so
use `export_evidence_bundle` before closing to keep findings.

**Admitted targets.** Header-detected: ELF, PE, Mach-O, DOS MZ. Everything
else needs an explicit format on `open_binary` / the CLI:

- DOS COM: `format: "dos-com"` (`--target-format dos-com`); mapped at
  1000:0100, linear 0x10100.
- Headerless image: `format: "raw-binary"` plus `architecture` (x86,
  x86_64, arm, arm64, 6502, m68k) and `entry_point`, the address file
  offset 0 is mapped to. Neo Geo P-ROM example:
  `rea function p1.bin 0x000122 --target-format raw-binary --architecture m68k --entry-point 0x000000 --provider ghidra --json`
- 65816/SNES ROMs are not admitted (no SnesLoader, no 65816 language);
  that stays with the snes variant's `snes-analyze`.

**First query is slow.** `open_binary` only binds the target; the first
analysis tool call runs Ghidra import plus auto-analysis (330 s deadline,
`REA_GHIDRA_STARTUP_TIMEOUT_MS` raises it; `GHIDRA_HEADLESS_MAXMEM`,
default 2G, bounds the JVM). A timeout is returned by that first query;
close and reopen after changing the env in the registration.

**Discovery.** `rea doctor --provider ghidra --json` validates Ghidra 12.1.x
plus the JDK; `rea mcp doctor --json` starts the stdio server and lists the
catalog. `rea update` is unsupported (root-owned /opt/rea); the version is
the REA_VERSION pin in docker-compose.yml.

**Tools missing in Claude Code.** init-workspace.sh registers the server on
every launch (remove-then-add). Re-register manually with:

```bash
claude mcp remove rea
claude mcp add rea -e GHIDRA_INSTALL_DIR=/opt/ghidra -e REA_MCP_INPUT_SCHEMA_PROFILE=compact -- rea mcp
# android: also -e REA_JADX_MCP_JAR=/opt/jadx-mcp/jadx-headless-mcp.jar -e REA_APKTOOL_COMMAND=/usr/local/bin/apktool -e REA_ADB_PATH=/opt/android-sdk/platform-tools/adb -e REA_MITMDUMP_COMMAND=/opt/mitmproxy/.venv/bin/mitmdump
```

The android entry lists more -e variables because REA locates its JADX,
Apktool, adb and mitmdump providers only through them, and the MCP entry
cannot rely on the environment of the shell that spawns it.

`claude mcp get rea` shows what init-workspace.sh registered. The compact profile keeps REA's ~200-tool catalog advertisement small. The
bundled skill `reverse-engineer-anything` is copied from /opt/rea into
~/.claude/skills on every launch, next to the claude-config skills; it stays
untracked there and is never committed to claude-config.
