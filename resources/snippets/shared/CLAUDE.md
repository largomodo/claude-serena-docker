# CLAUDE.md

Scripts shared by two or more variant Dockerfiles.

## Index

| File                | Contents (WHAT)                                                                                                                                                                       | Read When (WHEN)                                              |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `install-jdk.sh`    | Temurin JDK download, sidecar checksum verification, extraction to /opt/java/openjdk and CDS dump; args lang/version/build; used by java, java-docker, java-angular, x86, snes, 68k, kicad | Bumping the JDK, changing the Adoptium URL shape              |
| `install-ghidra.sh` | Ghidra release zip download with mandatory sha256, extraction to /opt/ghidra, analyzeHeadless symlink, codeuser ownership; args version/date/digest (x-ghidra-toolchain in docker-compose.yml); used by x86, snes, 68k | Bumping Ghidra, changing the release URL shape |
| `install-rea.sh`    | REA (npm rea-agents) global install into /opt/rea with the optional frida module removed, /usr/local/bin/rea symlink, version and bundled-skill checks; arg version (x-rea-toolchain); used by x86, 68k | Bumping REA, a build failing at the rea version or skill check |
| `install-jdtls.sh`  | JDT-LS download and extraction with --no-same-owner; args version/timestamp; used by java, java-docker, java-angular                                                                  | Bumping JDT-LS, rootless-DinD build failures at the jdtls tar |
| `install-lombok.sh` | Lombok jar download with mandatory sha256; args version/digest; used by java, java-docker, java-angular                                                                               | Bumping Lombok                                                |
| `dis16.sh`          | 16-bit x86 real-mode disassembly via ndisasm                                                                                                                                          | Modifying disassembly workflow, changing ndisasm flags        |
| `dump16.sh`         | 16-bit x86 objdump wrapper (i8086, Intel syntax)                                                                                                                                      | Modifying hex dump or objdump output format                   |
| `r216.sh`           | radare2 launcher pre-configured for 16-bit x86                                                                                                                                        | Modifying radare2 default settings for binary analysis        |

The `install-*.sh` scripts take versions and digests as positional arguments and exit 2 on a missing or empty one; the pins stay in docker-compose.yml or the calling Dockerfile. Each script's header comment states which Dockerfiles call it and which compose anchor owns its pins.
