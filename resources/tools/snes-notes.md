# snes notes

Condensed from resources/snippets/snes/snes-analyze.sh usage text and
resources/snippets/snes/CLAUDE.md; edit both.

`snes-analyze <rom.sfc|rom.smc> [analyzeHeadless options]` imports and
analyzes a SNES ROM: project name is derived from the ROM filename
(`<name>_snes`); `-loader SnesLoader` takes the loader's class name, not
its GUI display name ("SNES ROM"); processor is `65816:LE:16:default`.
`SeedSnesVectors.java` runs as a pre-script to seed disassembly from the
hardware vector table (RESET/NMI/IRQ/BRK/COP/ABORT) so auto-analysis has
real entry points; `SetSnesRegisters.java` sets 65816 register defaults;
`DumpInfo.java` prints a post-analysis summary.

Environment overrides: `GHIDRA_PROJECTS_DIR` (default
/workspace/.ghidra-projects), `GHIDRA_SCRIPTS_DIR` (default
/opt/ghidra/Ghidra/Scripts), `SNES_SEED_ARGS` (default `"1 1 0"`: native
mode 8-bit M/X flags, RESET-only emulation vector).

Extra `analyzeHeadless` options pass through, e.g.
`snes-analyze game.sfc -postScript ExportDisasm.java`.

Ghidra projects persist in /workspace/.ghidra-projects (gitignored by the
project). Re-importing the same ROM requires deleting the existing project
or passing a different project name.

This file is prose only: check-tools.sh verifies the sheet's `## Tools` and `## Environment` tables, never the content here.
