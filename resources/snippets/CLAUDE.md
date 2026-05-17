# CLAUDE.md

Variant-specific resources copied into variant Dockerfiles via COPY instructions.

## Index

| File / Directory | Contents (WHAT)                                                                  | Read When (WHEN)                                          |
| ---------------- | -------------------------------------------------------------------------------- | --------------------------------------------------------- |
| `README.md`      | Design rationale: why snippets are variant-scoped, shared/ deduplication strategy | Understanding directory structure and sharing model       |
| `snes/`          | SNES analysis scripts: snes-analyze.sh, SetSnesRegisters.java                    | Modifying SNES Ghidra analysis workflow                   |
| `shared/`        | Binary analysis helpers used by snes and x86 variants: dis16.sh, r216.sh, dump16.sh | Modifying disassembly or hex dump helpers              |
