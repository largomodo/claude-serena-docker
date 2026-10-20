# CLAUDE.md

Per-variant tool sheets concatenated at build time into the image and
imported into every Claude Code session as ~/.claude/claude-env.md.

## Index

| File | What | Read when |
| --- | --- | --- |
| `README.md` | Format contract, ownership split, token budget, notes-file source map | Adding or removing a sheet row, changing the format contract, a build failing at check-tools.sh |
| `base.md` | Shared toolchain sheet staged by Dockerfile.base into every variant | Changing a tool or env var common to all variants |
| `java.md` | `java`/`javac`/`jar`/`mvn` rows for the java variant | Changing the java toolchain |
| `java-docker.md` | java.md rows plus `docker` for the java-docker variant | Changing the java-docker toolchain |
| `java-angular.md` | java.md rows plus `node`/`npm`/`ng` for the java-angular variant | Changing the java-angular toolchain |
| `x86.md` | Ghidra/REA/nasm/radare2/dis16 rows, GHIDRA_INSTALL_DIR and the `rea` MCP server for the x86 variant | Changing the x86 toolchain |
| `snes.md` | x86.md rows plus `snes-analyze` and GHIDRA_* variables | Changing the snes toolchain |
| `68k.md` | vasm/vlink/mame/Ghidra/REA rows, GHIDRA_INSTALL_DIR and the `rea` MCP server for the 68k variant | Changing the 68k toolchain |
| `c.md` | `clangd` row; base gcc/g++/make notes | Changing the c variant's notes |
| `c-pico.md` | ARM/RISC-V toolchain, picotool, openocd, clangd rows | Changing the c-pico toolchain |
| `gowin.md` | Yosys/nextpnr/Apicula/openFPGALoader rows | Changing the gowin toolchain |
| `kicad.md` | kicad-cli/freeroute rows plus the kicad MCP server | Changing the kicad toolchain |
| `arduino.md` | arduino-cli/avr-gcc/avrdude/simavr/clangd rows plus ARDUINO_DIRECTORIES_* variables for the arduino variant | Changing the arduino toolchain |
| `image-dev.md` | `docker` rows for the image-dev variant | Changing the image-dev toolchain |
| `java-docker-notes.md` | Quarkus/Testcontainers/memory detail (read on demand) | Debugging java-docker container-died errors, dev mode connectivity |
| `java-angular-notes.md` | Dev server/proxy/test-runner detail (read on demand) | Setting up the Angular dev server, proxying /api, scaffolding a major |
| `snes-notes.md` | snes-analyze pipeline and Ghidra script detail (read on demand) | Analyzing a ROM, re-seeding vectors, exporting disassembly |
| `rea-notes.md` | REA admission rules (COM, raw m68k), first-query deadline, doctor commands, re-registration and skill placement (read on demand; staged by x86 and 68k) | Opening a headerless or COM target with REA, a REA timeout, `rea` missing from /mcp |
| `gowin-notes.md` | OSS vs Gowin EDA flow, USB/JTAG detail (read on demand) | Choosing a synthesis flow, flashing, debugging USB access |
| `kicad-notes.md` | Autoroute pipeline, MCP backend detail (read on demand) | Autorouting, scripting pcbnew, fixing a missing pcbnew module |
| `arduino-notes.md` | FQBN/bootloader, serial, compile-database and simavr recipes (read on demand) | Uploading to a Nano, a sync error, an .ino sketch Serena does not index, running firmware without a board |
