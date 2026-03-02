# CLAUDE.md

Containerized dev environment: Claude Code CLI + Serena agent + VASM/VLINK (m68k/z80) toolchain on Ubuntu 24.04.

## Index

| File / Directory                     | Contents (WHAT)                                                                 | Read When (WHEN)                                             |
| ------------------------------------ | ------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `Dockerfile`                         | Image definition: VASM, VLINK, Node.js, Claude Code CLI, Serena installs        | Modifying base image, adding packages, changing install order |
| `build.sh`                           | Image build script; passes host UID/GID as build args                           | Rebuilding the image, changing build-time args               |
| `launch.sh`                          | Container launch; host-side directory preparation, conditional .claude.json detection, bind mount arguments, docker run invocation | Changing startup behavior, bind mount configuration |
| `.gitignore`                         | Excludes `.env` (secrets) and `.claudeproject/` (runtime state)                 | Adding new gitignored paths                                  |
| `README.md`                          | User-facing usage guide: build, launch, authentication, configuration           | Understanding public-facing documentation                    |
| `resources/config/serena_config.yml` | Serena config template: LSP backend, dashboard port                             | Changing Serena behavior, dashboard address, tool timeout    |
| `resources/scripts/init-workspace.sh`| ENTRYPOINT: populates bind-mounted directories, session-exit .claude.json persistence, Serena indexing, MCP registration | Debugging container startup, changing init sequence |

## Build & Run

```bash
# Build the Docker image (uses host UID/GID for permission mapping)
./build.sh [optional_tag]

# Launch container with the neogeo-diag-bios source mounted at /workspace
./launch.sh /path/to/neogeo-diag-bios [optional_tag]
```

Inside the container, `claude` starts a session with Serena pre-registered as an MCP tool. The Serena web dashboard is available at `http://localhost:24282/dashboard/`.

### Neo Geo BIOS Compilation

The BIOS source directory is mounted to `/workspace`. Build commands:

```bash
# Build SP1 (68k System BIOS)
cd /workspace/sp1 && make

# Build M1 (Z80 Sound Driver)
cd /workspace/m1 && make
```

Verify artifacts:
- `sp1/output/sp1.bin` — System BIOS
- `m1/output/m1.bin` — Z80 Sound Driver
- `sp1/gen-crc-mirror` — Helper binary (compiled from C during make)
- `m1/gen-crc-mirror-bank` — Helper binary (compiled from C during make)

## Architecture

### Container Lifecycle

1. **Build time** (`Dockerfile`): Compiles VASM (m68k + z80 flavors) and VLINK from source, installs Node.js, Claude Code CLI, and Serena. Copies golden-master configs to `/usr/local/share/claude-env/`.
2. **Runtime entry** (`resources/scripts/init-workspace.sh`): The ENTRYPOINT script handles all runtime provisioning:
   - Creates `.claudeproject/` persistence directory in the mounted workspace (if absent)
   - `launch.sh` pre-creates `.claudeproject/.claude` and `.claudeproject/.serena` on the host and bind-mounts them to `~/.claude` and `~/.serena`
   - Clones/updates Claude config from `largomodo/claude-config` directly into `~/.claude/` (the bind-mounted directory)
   - Copies Serena config template into `~/.serena/` if not already present
   - On consecutive launches, `launch.sh` detects `hasCompletedOnboarding: true` in `.claudeproject/.claude.json` and bind-mounts it to `~/.claude.json`
   - On first launch, `~/.claude.json` is absent; after the interactive session ends, an EXIT trap copies it to `.claudeproject/.claude.json` for the next launch
   - Auto-detects source files (ASM, Python, Go, Rust, TypeScript) and runs `serena project create --language <detected>` + indexing; ASM is checked first for Neo Geo workflow compatibility
   - Registers Serena as MCP server via `claude mcp add`
3. **Interactive session**: Drops into bash; user runs `claude` to start AI-assisted coding, or invokes `make` directly in the sp1/m1 subdirectories

### Key Directories

- `/workspace` — mounted host project directory (container working directory)
- `/workspace/.claudeproject/` — persisted configs, auth tokens (gitignored)
- `/home/codeuser/serena/` — Serena installation (`$SERENA_HOME`)
- `/usr/local/bin/vasmm68k_mot` — Motorola 68000 assembler
- `/usr/local/bin/vasmz80_mot` — Zilog Z80 assembler
- `/usr/local/bin/vlink` — portable linker
- `/usr/local/share/claude-env/` — immutable config templates baked into image

### Configuration

- **Serena config template**: `resources/config/serena_config.yml` — uses LSP backend, web dashboard on `0.0.0.0:24282`, 240s tool timeout
- **Claude config**: Pulled from `github.com/largomodo/claude-config` (fork of `solatis/claude-config`)

### Authentication

Three methods are supported:

1. **`.env` file (recommended for daily use):** Create a `.env` file next to `launch.sh` containing `CLAUDE_CODE_OAUTH_TOKEN=<token>`. `launch.sh` sources it automatically on each run. The file is gitignored.
2. **OAuth Token env var:** Set `CLAUDE_CODE_OAUTH_TOKEN` on the host before running `launch.sh`. Shell exports take precedence over `.env` values when both are present.
3. **Interactive Login:** If no token is provided, run `claude` inside the container to authenticate. OAuth credentials are stored in `~/.claude/.credentials.json` (persisted to `.claudeproject/.claude/`) but expire after ~8 hours.

### Persistence Model

All mutable state lives in `.claudeproject/` at the workspace root, which is gitignored. `launch.sh` bind-mounts `.claudeproject/.claude` and `.claudeproject/.serena` directly to their `~/.` counterparts, making the persistence directory and the home directory the same filesystem location.

**`.claude.json` persistence uses two modes:**
- **Consecutive launch:** `launch.sh` detects `"hasCompletedOnboarding": true` in `.claudeproject/.claude.json` and bind-mounts it to `~/.claude.json`. Changes written by Claude Code during the session persist directly to the host file.
- **First launch:** No `.claude.json` exists in `.claudeproject/`. After the interactive session ends, an EXIT trap in `init-workspace.sh` copies `~/.claude.json` to `.claudeproject/.claude.json`. The next launch will then use the consecutive-launch path.

Configs and caches survive container restarts as long as the same host directory is mounted.

> **Note:** On first launch, `.claude.json` persistence depends on the EXIT trap firing when
> the session ends. `docker stop` (SIGTERM + 10s grace) triggers the trap normally. `docker kill`
> (SIGKILL) bypasses all traps; if the container is killed during a first-launch session, the
> `.claude.json` is not persisted and the next launch repeats the first-launch path. Use
> `docker stop` to terminate normally. (R-002)

### Troubleshooting

- **Endianness:** The neogeo-diag-bios `Makefile` uses `dd conv=swab`. The container environment (Ubuntu/x86_64) preserves standard little-endian behavior, which is sufficient for this byte-swap operation.
- **Permissions:** If artifacts created by Docker are root-owned on the host, run `chown -R $USER:$USER .` on the host after compilation.
- **VASM/VLINK not found:** Verify the toolchain is installed with `vasmm68k_mot --version` and `vlink --version` inside the container.
