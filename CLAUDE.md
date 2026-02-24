# CLAUDE.md

Containerized dev environment: Claude Code CLI + Serena agent + Java LSP (JDTLS) on Ubuntu 24.04.

## Index

| File / Directory                     | Contents (WHAT)                                                                 | Read When (WHEN)                                             |
| ------------------------------------ | ------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `Dockerfile`                         | Image definition: JDK, JDTLS, Node.js, Maven, Claude Code CLI, Serena installs | Modifying base image, adding packages, changing install order |
| `build.sh`                           | Image build script; passes host UID/GID as build args                           | Rebuilding the image, changing build-time args               |
| `launch.sh`                          | Container launch; host-side directory preparation, conditional .claude.json detection, bind mount arguments, docker run invocation | Changing startup behavior, bind mount configuration |
| `.gitignore`                         | Excludes `.env` (secrets) and `.claudeproject/` (runtime state)                 | Adding new gitignored paths                                  |
| `README.md`                          | User-facing usage guide: build, launch, authentication, configuration           | Understanding public-facing documentation                    |
| `resources/config/serena_config.yml` | Serena config template: LSP backend, dashboard port, JDTLS workspace path       | Changing Serena behavior, dashboard address, tool timeout    |
| `resources/scripts/init-workspace.sh`| ENTRYPOINT: populates bind-mounted directories, session-exit .claude.json persistence, Serena indexing, MCP registration | Debugging container startup, changing init sequence |
| `resources/scripts/jdtls.sh`         | JDTLS launcher: workspace arg, 2G heap, JDK path                                | Changing JDT Language Server settings                        |

## Build & Run

```bash
# Build the Docker image (uses host UID/GID for permission mapping)
./build.sh [optional_tag]

# Launch container with a host project mounted at /workspace
./launch.sh /path/to/your/java-project [optional_tag]
```

Inside the container, `claude` starts a session with Serena pre-registered as an MCP tool. The Serena web dashboard is available at `http://localhost:24282/dashboard/`.

## Architecture

### Container Lifecycle

1. **Build time** (`Dockerfile`): Installs JDK, JDTLS, Node.js, Maven, Claude Code CLI, and Serena. Copies golden-master configs to `/usr/local/share/claude-env/`.
2. **Runtime entry** (`resources/scripts/init-workspace.sh`): The ENTRYPOINT script handles all runtime provisioning:
   - Creates `.claudeproject/` persistence directory in the mounted workspace (if absent)
   - `launch.sh` pre-creates `.claudeproject/.claude`, `.claudeproject/.serena`, and `.claudeproject/.m2` on the host and bind-mounts them to `~/.claude`, `~/.serena`, and `~/.m2`
   - Clones/updates Claude config from `largomodo/claude-config` directly into `~/.claude/` (the bind-mounted directory)
   - Copies Serena config template into `~/.serena/` if not already present
   - On consecutive launches, `launch.sh` detects `hasCompletedOnboarding: true` in `.claudeproject/.claude.json` and bind-mounts it to `~/.claude.json`
   - On first launch, `~/.claude.json` is absent; after the interactive session ends, an EXIT trap copies it to `.claudeproject/.claude.json` for the next launch
   - Auto-detects source files (Java, Python, Go, Rust, TypeScript) and runs `serena project create --language <detected>` + indexing; Java is checked first for backward compatibility
   - Registers Serena as MCP server via `claude mcp add`
3. **Interactive session**: Drops into bash; user runs `claude` to start AI-assisted coding

### Key Directories

- `/workspace` — mounted host project directory (container working directory)
- `/workspace/.claudeproject/` — persisted configs, auth tokens, Maven cache (gitignored)
- `/home/codeuser/serena/` — Serena installation (`$SERENA_HOME`)
- `/opt/jdtls/` — Eclipse JDT Language Server installation
- `/opt/java/openjdk/` — JDK installation (`$JAVA_HOME`)
- `/usr/local/share/claude-env/` — immutable config templates baked into image

### JDTLS Cold-Start Handling

JDTLS has a known cold-start issue where Serena's 10-second LSP timeout is too short on first launch. The init script handles this with `serena_index_with_retry()` — up to 3 attempts with 5-second delays between failures. The first attempt warms JDTLS internally; subsequent attempts succeed.

### Configuration

- **Serena config template**: `resources/config/serena_config.yml` — uses LSP backend, web dashboard on `0.0.0.0:24282`, 240s tool timeout, JDTLS workspace at `/workspace/.jdtls-workspace`
- **JDTLS launcher**: `resources/scripts/jdtls.sh` — accepts `--workspace=` arg, runs with 2G max heap
- **Claude config**: Pulled from `github.com/largomodo/claude-config` (fork of `solatis/claude-config`)

### Authentication

Three methods are supported:

1. **`.env` file (recommended for daily use):** Create a `.env` file next to `launch.sh` containing `CLAUDE_CODE_OAUTH_TOKEN=<token>`. `launch.sh` sources it automatically on each run. The file is gitignored.
2. **OAuth Token env var:** Set `CLAUDE_CODE_OAUTH_TOKEN` on the host before running `launch.sh`. Shell exports take precedence over `.env` values when both are present.
3. **Interactive Login:** If no token is provided, run `claude` inside the container to authenticate. OAuth credentials are stored in `~/.claude/.credentials.json` (persisted to `.claudeproject/.claude/`) but expire after ~8 hours.

### Persistence Model

All mutable state lives in `.claudeproject/` at the workspace root, which is gitignored. `launch.sh` bind-mounts `.claudeproject/.claude`, `.claudeproject/.serena`, and `.claudeproject/.m2` directly to their `~/.` counterparts, making the persistence directory and the home directory the same filesystem location.

**`.claude.json` persistence uses two modes:**
- **Consecutive launch:** `launch.sh` detects `"hasCompletedOnboarding": true` in `.claudeproject/.claude.json` and bind-mounts it to `~/.claude.json`. Changes written by Claude Code during the session persist directly to the host file.
- **First launch:** No `.claude.json` exists in `.claudeproject/`. After the interactive session ends, an EXIT trap in `init-workspace.sh` copies `~/.claude.json` to `.claudeproject/.claude.json`. The next launch will then use the consecutive-launch path.

Configs and caches survive container restarts as long as the same host directory is mounted.

> **Note:** On first launch, `.claude.json` persistence depends on the EXIT trap firing when
> the session ends. `docker stop` (SIGTERM + 10s grace) triggers the trap normally. `docker kill`
> (SIGKILL) bypasses all traps; if the container is killed during a first-launch session, the
> `.claude.json` is not persisted and the next launch repeats the first-launch path. Use
> `docker stop` to terminate normally. (R-002)
