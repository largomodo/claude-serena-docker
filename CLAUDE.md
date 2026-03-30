# CLAUDE.md

> DL-001 (Ghidra 12.0.4), DL-003 (ViewtifulSlayer forks), DL-007 (snes-analyze wrapper), DL-006 (GHIDRA_PROJECTS_DIR persistence)

Containerized dev environment: Claude Code CLI + Serena agent + x86 DOS and SNES ROM disassembly toolchain on Ubuntu 24.04.

## Index

| File / Directory                       | Contents (WHAT)                                                                       | Read When (WHEN)                                              |
| -------------------------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `Dockerfile`                           | Image definition: JDK 21 (Ghidra), ndisasm, radare2, Ghidra 12.0.4 headless, SNES loader/65816 processor build, capstone, pefile, Claude Code CLI, Serena | Modifying base image, adding packages, upgrading Ghidra, changing install order |
| `build.sh`                             | Image build script; passes host UID/GID as build args                                 | Rebuilding the image, changing build-time args                |
| `launch.sh`                            | Container launch; host-side directory preparation, conditional .claude.json detection, bind mount arguments, docker run invocation | Changing startup behavior, bind mount configuration |
| `.gitignore`                           | Excludes `.env` (secrets), `.claudeproject/` (runtime state), `.ghidra-projects/` (Ghidra project files) | Adding new gitignored paths                                   |
| `README.md`                            | User-facing usage guide: build, launch, authentication, configuration                 | Understanding public-facing documentation                     |
| `resources/config/serena_config.yml`   | Serena config template: no language servers, dashboard port, workspace path           | Changing Serena behavior, dashboard address, tool timeout     |
| `resources/scripts/init-workspace.sh`  | ENTRYPOINT: populates bind-mounted directories, session-exit .claude.json persistence, binary file detection, MCP registration | Debugging container startup, changing init sequence |
| `resources/scripts/dis16.sh`           | Wrapper: `ndisasm -b 16` with usage message on no-arg invocation                      | Changing 16-bit ndisasm defaults                              |
| `resources/scripts/r216.sh`            | Wrapper: `r2 -b 16` (radare2 in 16-bit mode)                                         | Changing 16-bit radare2 defaults                              |
| `resources/scripts/dump16.sh`          | Wrapper: `objdump` with 16-bit i8086 disassembly flags                               | Changing objdump disassembly defaults                         |
| `resources/scripts/snes-analyze.sh`    | Wrapper: `analyzeHeadless` with SNES loader, 65816 processor, and SetSnesRegisters post-script | Analyzing SNES ROMs, changing analyzeHeadless SNES defaults |
| `resources/scripts/SetSnesRegisters.java` | GhidraScript: sets ctx_MF/ctx_XF/ctx_EF context registers and DBR/PBR/DP/SP at ROM entry point | Changing default 65816 register initialization             |
| `ghidra-snes-headless-setup.md`        | Maintainer reference: Dockerfile SNES build steps, nested-extraction guard, Sleigh pre-compilation, validation commands | Upgrading Ghidra, modifying SNES toolchain build, troubleshooting image builds |
| `ghidra-snes-headless-usage.md`        | User guide: snes-analyze wrapper, analyzeHeadless invocations, register flag overrides, batch import, project management | Running SNES analysis, overriding processor mode flags, scripting analysis |

## Build & Run

```bash
# Build the Docker image (uses host UID/GID for permission mapping)
./build.sh [optional_tag]

# Launch container with a host binary project mounted at /workspace
./launch.sh /path/to/your/binary-project [optional_tag]
```

Inside the container, `claude` starts a session with Serena pre-registered as an MCP tool. The Serena web dashboard is available at `http://localhost:24282/dashboard/`.

## Architecture

### Container Lifecycle

1. **Build time** (`Dockerfile`): Installs JDK 21 (required by Ghidra headless), ndisasm (NASM suite), radare2, Ghidra 12.0.4 headless, capstone, pefile, Claude Code CLI, and Serena. Builds the ViewtifulSlayer SNES loader extension and 65816 processor module, pre-compiles the Sleigh spec, and bakes `SetSnesRegisters.java` into the image. Copies golden-master configs to `/usr/local/share/claude-env/`.
2. **Runtime entry** (`resources/scripts/init-workspace.sh`): The ENTRYPOINT script handles all runtime provisioning:
   - Creates `.claudeproject/` persistence directory in the mounted workspace (if absent)
   - `launch.sh` pre-creates `.claudeproject/.claude` and `.claudeproject/.serena` on the host and bind-mounts them to `~/.claude` and `~/.serena`
   - Clones/updates Claude config from `largomodo/claude-config` directly into `~/.claude/` (the bind-mounted directory)
   - Copies Serena config template into `~/.serena/` if not already present
   - On consecutive launches, `launch.sh` detects `hasCompletedOnboarding: true` in `.claudeproject/.claude.json` and bind-mounts it to `~/.claude.json`
   - On first launch, `~/.claude.json` is absent; after the interactive session ends, an EXIT trap copies it to `.claudeproject/.claude.json` for the next launch
   - Detects binary files (.com, .exe, .asm) and SNES ROMs (.sfc, .smc) and logs architecture-specific tool recommendations; does not call `serena project create` (no binary/asm language exists in Serena)
   - Creates `$GHIDRA_PROJECTS_DIR` (`/workspace/.ghidra-projects`) for Ghidra project persistence
   - Registers Serena as MCP server via `claude mcp add`
3. **Interactive session**: Drops into bash; user runs `claude` to start AI-assisted coding

### Key Directories

- `/workspace` — mounted host project directory (container working directory)
- `/workspace/.claudeproject/` — persisted configs and auth tokens (gitignored)
- `/workspace/.ghidra-projects/` — Ghidra project files created by `snes-analyze` and `analyzeHeadless` (`$GHIDRA_PROJECTS_DIR`, gitignored)
- `/home/codeuser/serena/` — Serena installation (`$SERENA_HOME`)
- `/opt/ghidra/` — Ghidra 12.0.4 headless installation; `analyzeHeadless` symlinked to `/usr/local/bin/`
- `/opt/ghidra/Ghidra/Extensions/SnesLoader/` — SNES loader extension (extracted at build time)
- `/opt/ghidra/Ghidra/Processors/65816/` — 65816 processor module with pre-compiled Sleigh spec (`65816.sla`)
- `/opt/ghidra/Ghidra/Scripts/` — GhidraScripts directory (`$GHIDRA_SCRIPTS_DIR`); contains `SetSnesRegisters.java`
- `/opt/java/openjdk/` — JDK 21 installation (`$JAVA_HOME`); required by Ghidra
- `/usr/local/share/claude-env/` — immutable config templates baked into image
- `/usr/local/bin/dis16`, `/usr/local/bin/r216`, `/usr/local/bin/dump16` — 16-bit x86 mode wrapper scripts
- `/usr/local/bin/snes-analyze` — SNES ROM analysis wrapper script

### Disassembly Toolchain

All DOS binaries are 16-bit real mode. Every tool defaults to 32/64-bit; the wrapper scripts enforce correct flags automatically.

| Wrapper          | Underlying Tool         | Target Architecture         |
| ---------------- | ----------------------- | --------------------------- |
| `dis16`          | ndisasm (`-b 16`)       | x86 DOS 16-bit real mode    |
| `r216`           | radare2 (`-b 16`)       | x86 DOS 16-bit real mode    |
| `dump16`         | objdump (`-m i8086`)    | x86 DOS 16-bit real mode    |
| `snes-analyze`   | analyzeHeadless         | SNES ROM (65816 processor)  |

Ghidra headless (`analyzeHeadless`) accepts:
- `x86:LE:16:Real Mode:default` for x86 DOS 16-bit real-mode analysis
- `65816:LE:16:default` for SNES ROM analysis (via `snes-analyze` wrapper)

The SNES toolchain uses:
- Loader: `SNES ROM` (ViewtifulSlayer/ghidra-snes-loader extension)
- Processor: `65816:LE:16:default` (ViewtifulSlayer/ghidra-65816 module)
- Post-script: `SetSnesRegisters.java` sets context registers `ctx_MF`/`ctx_XF`/`ctx_EF` and physical registers `DBR`/`PBR`/`DP`/`SP` at the ROM entry point

Python libraries `capstone` and `pefile` are installed globally for scripted analysis.

### Configuration

- **Serena config template**: `resources/config/serena_config.yml` — no language servers configured (`language_servers: {}`), web dashboard on `0.0.0.0:24282`, 240s tool timeout
- **Claude config**: Pulled from `github.com/largomodo/claude-config` (fork of `solatis/claude-config`)

### Authentication

Three methods are supported:

1. **`.env` file (recommended for daily use):** Create a `.env` file next to `launch.sh` containing `CLAUDE_CODE_OAUTH_TOKEN=<token>`. `launch.sh` sources it automatically on each run. The file is gitignored.
2. **OAuth Token env var:** Set `CLAUDE_CODE_OAUTH_TOKEN` on the host before running `launch.sh`. Shell exports take precedence over `.env` values when both are present.
3. **Interactive Login:** If no token is provided, run `claude` inside the container to authenticate. OAuth credentials are stored in `~/.claude/.credentials.json` (persisted to `.claudeproject/.claude/`) but expire after ~8 hours.

### Persistence Model

All mutable state lives in `.claudeproject/` at the workspace root, which is gitignored. `launch.sh` bind-mounts `.claudeproject/.claude` and `.claudeproject/.serena` directly to their `~/.` counterparts.

**`.claude.json` persistence uses two modes:**
- **Consecutive launch:** `launch.sh` detects `"hasCompletedOnboarding": true` in `.claudeproject/.claude.json` and bind-mounts it to `~/.claude.json`. Changes written by Claude Code during the session persist directly to the host file.
- **First launch:** No `.claude.json` exists in `.claudeproject/`. After the interactive session ends, an EXIT trap in `init-workspace.sh` copies `~/.claude.json` to `.claudeproject/.claude.json`. The next launch will then use the consecutive-launch path.

Configs survive container restarts as long as the same host directory is mounted.

> **Note:** On first launch, `.claude.json` persistence depends on the EXIT trap firing when
> the session ends. `docker stop` (SIGTERM + 10s grace) triggers the trap normally. `docker kill`
> (SIGKILL) bypasses all traps; if the container is killed during a first-launch session, the
> `.claude.json` is not persisted and the next launch repeats the first-launch path. Use
> `docker stop` to terminate normally. (R-002)
