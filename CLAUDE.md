# CLAUDE.md

Containerized dev environment: Claude Code CLI + Serena agent + x86 DOS disassembly toolchain on Ubuntu 24.04.

## Index

| File / Directory                       | Contents (WHAT)                                                                       | Read When (WHEN)                                              |
| -------------------------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `Dockerfile`                           | Image definition: JDK 21 (Ghidra), ndisasm, radare2, Ghidra headless, capstone, pefile, Claude Code CLI, Serena | Modifying base image, adding packages, changing install order |
| `build.sh`                             | Image build script; passes host UID/GID as build args                                 | Rebuilding the image, changing build-time args                |
| `launch.sh`                            | Container launch; host-side directory preparation, conditional .claude.json detection, bind mount arguments, docker run invocation | Changing startup behavior, bind mount configuration |
| `.gitignore`                           | Excludes `.env` (secrets) and `.claudeproject/` (runtime state)                       | Adding new gitignored paths                                   |
| `README.md`                            | User-facing usage guide: build, launch, authentication, configuration                 | Understanding public-facing documentation                     |
| `resources/config/serena_config.yml`   | Serena config template: no language servers, dashboard port, workspace path           | Changing Serena behavior, dashboard address, tool timeout     |
| `resources/scripts/init-workspace.sh`  | ENTRYPOINT: populates bind-mounted directories, session-exit .claude.json persistence, binary file detection, MCP registration | Debugging container startup, changing init sequence |
| `resources/scripts/dis16.sh`           | Wrapper: `ndisasm -b 16` with usage message on no-arg invocation                      | Changing 16-bit ndisasm defaults                              |
| `resources/scripts/r216.sh`            | Wrapper: `r2 -b 16` (radare2 in 16-bit mode)                                         | Changing 16-bit radare2 defaults                              |
| `resources/scripts/dump16.sh`          | Wrapper: `objdump` with 16-bit i8086 disassembly flags                               | Changing objdump disassembly defaults                         |

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

1. **Build time** (`Dockerfile`): Installs JDK 21 (required by Ghidra headless), ndisasm (NASM suite), radare2, Ghidra headless, capstone, pefile, Claude Code CLI, and Serena. Copies golden-master configs to `/usr/local/share/claude-env/`.
2. **Runtime entry** (`resources/scripts/init-workspace.sh`): The ENTRYPOINT script handles all runtime provisioning:
   - Creates `.claudeproject/` persistence directory in the mounted workspace (if absent)
   - `launch.sh` pre-creates `.claudeproject/.claude` and `.claudeproject/.serena` on the host and bind-mounts them to `~/.claude` and `~/.serena`
   - Clones/updates Claude config from `largomodo/claude-config` directly into `~/.claude/` (the bind-mounted directory)
   - Copies Serena config template into `~/.serena/` if not already present
   - On consecutive launches, `launch.sh` detects `hasCompletedOnboarding: true` in `.claudeproject/.claude.json` and bind-mounts it to `~/.claude.json`
   - On first launch, `~/.claude.json` is absent; after the interactive session ends, an EXIT trap copies it to `.claudeproject/.claude.json` for the next launch
   - Detects binary files (.com, .exe, .asm) and logs presence; does not call `serena project create` (no binary/asm language exists in Serena)
   - Registers Serena as MCP server via `claude mcp add`
3. **Interactive session**: Drops into bash; user runs `claude` to start AI-assisted coding

### Key Directories

- `/workspace` — mounted host project directory (container working directory)
- `/workspace/.claudeproject/` — persisted configs and auth tokens (gitignored)
- `/home/codeuser/serena/` — Serena installation (`$SERENA_HOME`)
- `/opt/ghidra/` — Ghidra headless installation; `analyzeHeadless` symlinked to `/usr/local/bin/`
- `/opt/java/openjdk/` — JDK 21 installation (`$JAVA_HOME`); required by Ghidra
- `/usr/local/share/claude-env/` — immutable config templates baked into image
- `/usr/local/bin/dis16`, `/usr/local/bin/r216`, `/usr/local/bin/dump16` — 16-bit mode wrapper scripts

### Disassembly Toolchain

All DOS binaries are 16-bit real mode. Every tool defaults to 32/64-bit; the wrapper scripts enforce correct flags automatically.

| Wrapper    | Underlying Tool | 16-bit Flag Applied |
| ---------- | --------------- | ------------------- |
| `dis16`    | ndisasm         | `-b 16`             |
| `r216`     | radare2 (`r2`)  | `-b 16`             |
| `dump16`   | objdump         | `-m i8086`          |

Ghidra headless (`analyzeHeadless`) accepts processor string `x86:LE:16:Real Mode:default` for 16-bit real-mode analysis.

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
