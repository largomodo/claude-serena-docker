# CLAUDE.md

Variant-specific resources copied into variant Dockerfiles via COPY instructions.

## Index

| File / Directory | Contents (WHAT)                                                                  | Read When (WHEN)                                          |
| ---------------- | -------------------------------------------------------------------------------- | --------------------------------------------------------- |
| `README.md`      | Design rationale: why snippets are variant-scoped, shared/ deduplication strategy | Understanding directory structure and sharing model       |
| `snes/`          | SNES analysis scripts: snes-analyze.sh, SetSnesRegisters.java                    | Modifying SNES Ghidra analysis workflow                   |
| `android/`       | Android wrapper scripts installed to /usr/local/bin: apktool.sh, blutter.sh, il2cppdumper.sh | Changing Apktool options, blutter cache layout, .NET roll-forward |
| `shared/`        | Binary analysis helpers used by snes and x86 (dis16.sh, r216.sh, dump16.sh), Java toolchain install scripts (install-jdk.sh, install-jdtls.sh, install-lombok.sh) used by every JDK-bearing variant, install-ghidra.sh (x86, snes, 68k, android) and install-rea.sh (x86, 68k, android) | Modifying disassembly helpers or the JDK/JDT-LS/Lombok/Ghidra/REA install procedures |
