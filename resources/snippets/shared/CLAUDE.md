# CLAUDE.md

Scripts shared by two or more variant Dockerfiles.

## Index

| File                | Contents (WHAT)                                                                                                                                                                       | Read When (WHEN)                                              |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `install-jdk.sh`    | Temurin JDK download, sidecar checksum verification, extraction to /opt/java/openjdk and CDS dump; args lang/version/build; used by java, java-docker, java-angular, x86, snes, kicad | Bumping the JDK, changing the Adoptium URL shape              |
| `install-jdtls.sh`  | JDT-LS download and extraction with --no-same-owner; args version/timestamp; used by java, java-docker, java-angular                                                                  | Bumping JDT-LS, rootless-DinD build failures at the jdtls tar |
| `install-lombok.sh` | Lombok jar download with mandatory sha256; args version/digest; used by java, java-docker, java-angular                                                                               | Bumping Lombok                                                |
| `dis16.sh`          | 16-bit x86 real-mode disassembly via ndisasm                                                                                                                                          | Modifying disassembly workflow, changing ndisasm flags        |
| `dump16.sh`         | 16-bit x86 objdump wrapper (i8086, Intel syntax)                                                                                                                                      | Modifying hex dump or objdump output format                   |
| `r216.sh`           | radare2 launcher pre-configured for 16-bit x86                                                                                                                                        | Modifying radare2 default settings for binary analysis        |

The `install-*.sh` scripts take versions and digests as positional arguments and exit 2 on a missing or empty one; the pins stay in docker-compose.yml or the calling Dockerfile.
