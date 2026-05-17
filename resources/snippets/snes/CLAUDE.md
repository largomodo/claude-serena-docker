# CLAUDE.md

SNES ROM analysis resources for the Ghidra-based snes variant.

## Index

| File                     | Contents (WHAT)                                                        | Read When (WHEN)                                           |
| ------------------------ | ---------------------------------------------------------------------- | ---------------------------------------------------------- |
| `snes-analyze.sh`        | Ghidra headless import+analysis for SNES ROMs (65816 processor, SNES ROM loader) | Modifying SNES analysis workflow, changing Ghidra flags |
| `SetSnesRegisters.java`  | Ghidra post-analysis script: sets 65816 register defaults for SNES context | Modifying register initialization, debugging Ghidra analysis |
