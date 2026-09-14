# claude-env container toolchain: snes

Same Tools rows as x86, plus the SNES analysis wrapper.

## Tools (snes)

| Tool | What | Use when |
| --- | --- | --- |
| `nasm` `ndisasm` | Netwide Assembler and disassembler | Assembling or disassembling code |
| `r2` | radare2 | Interactive binary analysis, scripting |
| `upx` | UPX packer/unpacker | Unpacking a compressed executable |
| `analyzeHeadless` | Ghidra 12 headless (/opt/ghidra), SNES loader | Batch import/auto-analysis of a binary |
| `dis16` `r216` `dump16` | 16-bit helpers wrapping ndisasm/r2/objdump | Disassembling or hex-dumping 16-bit code |
| `java` | JDK, required by Ghidra | Debugging a Ghidra headless launch failure |
| `snes-analyze` | One-shot Ghidra import+analysis of a .sfc/.smc ROM | Analyzing a SNES ROM |

## Environment (snes)

| Variable | What |
| --- | --- |
| `VARIANT` | Container variant name (`snes`) |
| `JAVA_HOME` | JDK installation root |
| `GHIDRA_SCRIPTS_DIR` | Scripts dir (SetSnesRegisters, SeedSnesVectors, DumpInfo) |
| `GHIDRA_PROJECTS_DIR` | Ghidra project storage directory |

## Notes (snes)

- Binary analysis variant: no Serena project is created; Serena's file tools still work.
- Read /usr/local/share/claude-env/tools/snes-notes.md for ROM analysis, re-seeding vectors, or exporting disassembly.
- Presence on PATH is what the build verifies; it does not guarantee a tool succeeds for every invocation.
