# Ghidra Headless SNES Environment — Usage Guide

> **Audience:** Senior developer performing SNES ROM analysis using the containerized dev environment.
> Register names ctx_MF/ctx_XF/ctx_EF match the 65816 .slaspec bitfield definitions (DL-005);
> using bare names (without the ctx_ prefix) causes a silent no-op.
> Ghidra, the SNES loader, and the 65816 processor module are pre-installed in the Docker image.
> No setup is required; run `snes-analyze` or `analyzeHeadless` directly inside the container.

---

## 1. Environment Variables

These are set automatically in the container:

| Variable | Value | Purpose |
|----------|-------|---------|
| `GHIDRA_PROJECTS_DIR` | `/workspace/.ghidra-projects` | Ghidra project storage (persists to host) |
| `GHIDRA_SCRIPTS_DIR` | `/opt/ghidra/Ghidra/Scripts` | GhidraScripts directory |

The following values are fixed in the container:

| Parameter | Value |
|-----------|-------|
| Loader name (`-loader`) | `SNES ROM` |
| Language ID (`-processor`) | `65816:LE:16:default` |
| Compiler spec (`-cspec`) | `default` |
| Ghidra version | `12.0.4` |

---

## 2. Quick Start: snes-analyze Wrapper

The `snes-analyze` wrapper handles all required flags automatically. This is the recommended entry point for most SNES analysis:

```bash
snes-analyze /workspace/game.sfc
```

What this does:
1. Creates a Ghidra project named `game_snes` under `$GHIDRA_PROJECTS_DIR`.
2. Imports `game.sfc` using the SNES ROM loader (LoROM/HiROM detection, address space mapping).
3. Assigns the 65816 processor and compiler spec.
4. Runs `SetSnesRegisters.java` after import, which sets context registers (`ctx_MF`, `ctx_XF`, `ctx_EF`) and physical registers (`DBR`, `PBR`, `DP`, `SP`) at the program entry point.
5. Runs Ghidra's auto-analysis.
6. Saves the analyzed program to the project.

To pass additional flags to `analyzeHeadless`, append them after the ROM path:

```bash
snes-analyze /workspace/game.sfc -noanalysis
```

> **Warning:** `snes-analyze` already passes `-postScript SetSnesRegisters.java` with default register arguments internally. Passing another `-postScript SetSnesRegisters.java` via `"$@"` results in two sequential postScript invocations. To override register flags, call `analyzeHeadless` directly (see section 3) instead of using the wrapper.

---

## 3. Basic Import and Analysis (analyzeHeadless directly)

For fine-grained control, call `analyzeHeadless` directly:

### 3.1 Import a ROM, set registers, and run auto-analysis

```bash
analyzeHeadless \
  "$GHIDRA_PROJECTS_DIR" MyProject \
  -import /workspace/game.sfc \
  -loader "SNES ROM" \
  -processor "65816:LE:16:default" \
  -cspec default \
  -scriptPath "$GHIDRA_SCRIPTS_DIR" \
  -postScript SetSnesRegisters.java \
  -log /tmp/ghidra_import.log
```

### 3.2 Import without analysis (inspect first, analyze later)

```bash
analyzeHeadless \
  "$GHIDRA_PROJECTS_DIR" MyProject \
  -import /workspace/game.sfc \
  -loader "SNES ROM" \
  -processor "65816:LE:16:default" \
  -cspec default \
  -scriptPath "$GHIDRA_SCRIPTS_DIR" \
  -postScript SetSnesRegisters.java \
  -noanalysis \
  -log /tmp/ghidra_import.log
```

The `-noanalysis` flag skips auto-analysis. The ROM is imported and registers are set, but no disassembly or data-flow analysis is performed. You can run analysis later with `-process` (see section 4).

---

## 4. Processing Previously Imported Programs

To run analysis or scripts on a ROM that is already in a Ghidra project, use `-process` instead of `-import`:

### 4.1 Run analysis on an existing program

```bash
analyzeHeadless \
  "$GHIDRA_PROJECTS_DIR" MyProject \
  -process "game.sfc" \
  -scriptPath "$GHIDRA_SCRIPTS_DIR" \
  -log /tmp/ghidra_process.log
```

The program name in `-process` must match the name Ghidra assigned at import time (typically the filename).

### 4.2 Run a script against an existing program without re-analyzing

```bash
analyzeHeadless \
  "$GHIDRA_PROJECTS_DIR" MyProject \
  -process "game.sfc" \
  -noanalysis \
  -scriptPath "$GHIDRA_SCRIPTS_DIR" \
  -postScript YourCustomScript.java \
  -log /tmp/ghidra_script.log
```

### 4.3 Process all programs in a project

```bash
analyzeHeadless \
  "$GHIDRA_PROJECTS_DIR" MyProject \
  -process \
  -scriptPath "$GHIDRA_SCRIPTS_DIR" \
  -postScript ExportFunctions.java \
  -noanalysis \
  -readOnly \
  -log /tmp/ghidra_batch.log
```

Omitting the program name after `-process` processes every program in the project. The `-readOnly` flag ensures no changes are saved back (useful for export-only scripts).

---

## 5. Overriding Processor Mode Flags

The default `SetSnesRegisters.java` script uses native mode with 16-bit accumulator and 16-bit index registers. Many SNES games start in a different configuration. Override via script arguments:

```bash
-postScript SetSnesRegisters.java 1 1 0
```

The three arguments are positional:

| Position | Register | 0 | 1 |
|----------|----------|---|---|
| arg0 | `ctx_MF` | 16-bit accumulator | 8-bit accumulator |
| arg1 | `ctx_XF` | 16-bit index registers | 8-bit index registers |
| arg2 | `ctx_EF` | Native mode | Emulation mode |

These correspond to the context register bitfields `ctx_MF`, `ctx_XF`, and `ctx_EF` defined in the 65816 `.slaspec`. The physical registers `DBR`, `PBR`, `DP`, and `SP` are always initialized to reset-state defaults.

Most SNES games reset into **emulation mode** (`ctx_EF=1`), which implies 8-bit accumulator and 8-bit index, then switch to native mode early in their init code. To match this:

```bash
-postScript SetSnesRegisters.java 1 1 1
```

Or with the wrapper:

```bash
snes-analyze /workspace/game.sfc -postScript SetSnesRegisters.java 1 1 1
```

If you are unsure, start with emulation mode (`1 1 1`) — this matches the hardware reset state. Ghidra may not track the mode switch automatically (a known limitation of the 65816 module), so you may need to re-process with different flags for code that runs after the mode switch.

---

## 6. Batch Import of Multiple ROMs

```bash
analyzeHeadless \
  "$GHIDRA_PROJECTS_DIR" SnesBatch \
  -import /workspace/roms/ \
  -loader "SNES ROM" \
  -processor "65816:LE:16:default" \
  -cspec default \
  -scriptPath "$GHIDRA_SCRIPTS_DIR" \
  -postScript SetSnesRegisters.java 1 1 1 \
  -recursive \
  -log /tmp/ghidra_batch_import.log
```

This imports every file in `/workspace/roms/` (and subdirectories, due to `-recursive`). Files that the SNES loader does not recognize will fail to import and be skipped; check the log for details.

Note that the same register configuration is applied to every ROM. If different ROMs need different settings, import them in separate batches or write a script that inspects the ROM header to determine the correct flags.

---

## 7. Exporting Results

### 7.1 Export disassembly to a text file

Create a post-script (`ExportDisassembly.java`) in `$GHIDRA_SCRIPTS_DIR`:

```java
// @category SNES
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import java.io.*;

public class ExportDisassembly extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        String outPath = (args.length > 0) ? args[0] : "/tmp/disasm_output.txt";

        try (PrintWriter pw = new PrintWriter(new FileWriter(outPath))) {
            InstructionIterator it = currentProgram.getListing().getInstructions(true);
            while (it.hasNext()) {
                Instruction instr = it.next();
                pw.printf("%s  %s  %s%n",
                    instr.getAddress(),
                    instr.toString(),
                    instr.getMnemonicString());
            }
        }
        println("Exported to " + outPath);
    }
}
```

Invoke:

```bash
analyzeHeadless \
  "$GHIDRA_PROJECTS_DIR" MyProject \
  -process "game.sfc" \
  -noanalysis \
  -readOnly \
  -scriptPath "$GHIDRA_SCRIPTS_DIR" \
  -postScript ExportDisassembly.java /workspace/game_disasm.txt
```

### 7.2 Export using Ghidra's built-in exporters

Ghidra's headless mode does not expose the File -> Export menu. To use built-in export formats (e.g., C/C++ decompilation, XML, HTML), you need a script that invokes the exporter API programmatically. Consult the `GhidraScript` API documentation under `/opt/ghidra/docs/GhidraAPI_javadoc.zip`.

---

## 8. Known Limitations of the 65816 Processor Module

These affect analysis results regardless of headless vs. GUI mode:

- **Processor mode tracking:** Ghidra does not automatically update `ctx_MF`/`ctx_XF` when the code executes `PLP` or `RTI` (which pull flags from the stack). Instructions after a mode change may be disassembled with the wrong operand sizes. You may need to re-import or re-process segments of code with corrected register values.
- **Interrupt vectors:** The reset, NMI, IRQ, and BRK vectors defined in the ROM header are not automatically marked as entry points. If you need to analyze interrupt handlers, write a script that reads the vector table and creates entry points.
- **Decompilation quality:** The 65816 module authors note that decompiled output is often unusable. Rely on the disassembly listing rather than the decompiler for SNES code.
- **Bank boundary wrapping:** Disassembly and data-flow analysis will be incorrect when an instruction and its operands wrap at the end of a 64 KB program bank.

---

## 9. Project Management

### 9.1 One project per ROM vs. shared projects

For focused analysis, create a separate project per ROM (the `snes-analyze` wrapper does this automatically using the ROM filename):

```bash
snes-analyze /workspace/game.sfc   # project: game_snes
```

For batch work across many ROMs, specify a project name directly:

```bash
analyzeHeadless "$GHIDRA_PROJECTS_DIR" SnesBatch -import /workspace/roms/ ...
```

Ghidra projects are directories on disk under `$GHIDRA_PROJECTS_DIR`. Each project contains a `.gpr` file and a `.rep` folder. The `$GHIDRA_PROJECTS_DIR` directory (`/workspace/.ghidra-projects`) is bind-mounted to the host and is gitignored.

### 9.2 Overwriting a previously imported ROM

To re-import a ROM that already exists in a project (e.g., after changing register settings), add `-overwrite`:

```bash
analyzeHeadless \
  "$GHIDRA_PROJECTS_DIR" MyProject \
  -import /workspace/game.sfc \
  -overwrite \
  -loader "SNES ROM" \
  -processor "65816:LE:16:default" \
  -cspec default \
  -scriptPath "$GHIDRA_SCRIPTS_DIR" \
  -postScript SetSnesRegisters.java 1 1 1 \
  -log /tmp/ghidra_reimport.log
```

Without `-overwrite`, the headless analyzer skips files that are already in the project.

### 9.3 Temporary throwaway projects

For one-off analysis where you do not need to keep the project:

```bash
analyzeHeadless \
  /tmp TempProject \
  -import /workspace/game.sfc \
  -loader "SNES ROM" \
  -processor "65816:LE:16:default" \
  -cspec default \
  -scriptPath "$GHIDRA_SCRIPTS_DIR" \
  -postScript SetSnesRegisters.java 1 1 1 \
  -postScript ExportDisassembly.java /workspace/output.txt \
  -deleteProject \
  -log /tmp/ghidra_temp.log
```

The `-deleteProject` flag removes the project directory after all scripts complete. The exported output file at `/workspace/output.txt` is retained because it was written outside the project directory.

---

## 10. Memory Configuration

The default headless heap is 2 GB. SNES ROMs are small (up to 6 MB), so this is sufficient for single-ROM analysis. For large batch jobs, increase it:

```bash
export GHIDRA_HEADLESS_MAXMEM="4G"
```

Set this before running `analyzeHeadless` or `snes-analyze`.

---

## 11. Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| `No loader found for file` | SNES loader extension not discovered | Verify the extension is extracted (not zipped) in `/opt/ghidra/Ghidra/Extensions/` and that `extension.properties` is present at correct depth |
| `LanguageNotFoundException: 65816:LE:16:default` | Processor module not installed or language ID wrong | Verify the `65816` directory under `/opt/ghidra/Ghidra/Processors/` and confirm the exact language ID from `65816.ldefs` |
| `SleighException: can't read language spec` | Sleigh spec not compiled | Verify `/opt/ghidra/Ghidra/Processors/65816/data/languages/65816.sla` exists (should be pre-compiled at build time) |
| `Extension version mismatch` in log | Extension built against a different Ghidra version | Rebuild the Docker image so the loader is built against the installed Ghidra version |
| Disassembly shows wrong operand sizes | Processor mode flags set incorrectly | Re-import with different `SetSnesRegisters.java` arguments (see section 5) |
| Register not found: `ctx_MF` | Wrong register names in script | The 65816 `.slaspec` defines `ctx_MF`/`ctx_XF`/`ctx_EF` as context bitfields; verify `SetSnesRegisters.java` uses these names |
| Script not found | Script path not specified or incorrect | Confirm `-scriptPath` points to the directory containing the `.java` file; `$GHIDRA_SCRIPTS_DIR` is pre-set in the container |
| `JAVA_HOME` errors | JDK 21 not on PATH | `$JAVA_HOME` is set to `/opt/java/openjdk` in the container; this should not occur unless the environment was altered |

---

## 12. Quick Reference

### snes-analyze wrapper (recommended)

```bash
snes-analyze /workspace/game.sfc
snes-analyze /workspace/game.sfc -noanalysis
snes-analyze /workspace/game.sfc -postScript SetSnesRegisters.java 1 1 1
```

### Minimal direct analyzeHeadless command

```bash
analyzeHeadless \
  "$GHIDRA_PROJECTS_DIR" ProjectName \
  -import /workspace/rom.sfc \
  -loader "SNES ROM" \
  -processor "65816:LE:16:default" \
  -cspec default \
  -scriptPath "$GHIDRA_SCRIPTS_DIR" \
  -postScript SetSnesRegisters.java 1 1 1
```

### Useful flags

| Flag | Purpose |
|------|---------|
| `-noanalysis` | Skip auto-analysis (import or script-only) |
| `-readOnly` | Discard all changes on exit |
| `-overwrite` | Replace existing program in project |
| `-deleteProject` | Remove project after completion |
| `-recursive` | Import files from subdirectories |
| `-analysisTimeoutPerFile 300` | Set per-file analysis timeout (seconds) |
| `-log /path/to/file.log` | Write Ghidra log to specified file |
| `-scriptlog /path/to/script.log` | Separate log file for script output |
| `-max-cpu 4` | Limit CPU cores used |
