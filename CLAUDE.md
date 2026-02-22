# CLAUDE.md

Containerized dev environment: Claude Code CLI + Serena agent + Java LSP (JDTLS) on Ubuntu 24.04.

## Index

| File / Directory                     | Contents (WHAT)                                                                 | Read When (WHEN)                                             |
| ------------------------------------ | ------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `Dockerfile`                         | Image definition: JDK, JDTLS, Node.js, Maven, Claude Code CLI, Serena installs | Modifying base image, adding packages, changing install order |
| `build.sh`                           | Image build script; passes host UID/GID as build args                           | Rebuilding the image, changing build-time args               |
| `launch.sh`                          | Container launch; .env loading, token precedence, docker run invocation         | Changing startup behavior, auth token handling, .env support |
| `.gitignore`                         | Excludes `.env` (secrets) and `.claudeproject/` (runtime state)                 | Adding new gitignored paths                                  |
| `README.md`                          | User-facing usage guide: build, launch, authentication, configuration           | Understanding public-facing documentation                    |
| `resources/config/serena_config.yml` | Serena config template: LSP backend, dashboard port, JDTLS workspace path       | Changing Serena behavior, dashboard address, tool timeout    |
| `resources/scripts/init-workspace.sh`| ENTRYPOINT: runtime provisioning, symlinks, Serena indexing, MCP registration   | Debugging container startup, changing init sequence          |
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
   - Creates `.claudeproject/` persistence directory in the mounted workspace
   - Clones/updates Claude config from `largomodo/claude-config` into `.claudeproject/.claude/` and symlinks to `~/.claude`
   - Copies Serena config template into `.claudeproject/.serena/` and symlinks to `~/.serena`
   - Creates `.claudeproject/.m2/` for Maven cache persistence and symlinks to `~/.m2`
   - Persists auth tokens (`.claude.json`) across container restarts
   - Auto-detects Java source files and runs `serena project create --language java` + indexing
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
3. **Interactive Login:** If no token is provided, run `claude` inside the container to authenticate. OAuth credentials are stored in `~/.claude/.credentials.json` (persisted via the `.claudeproject` symlink) but expire after ~8 hours.

### Persistence Model

All mutable state lives in `.claudeproject/` at the workspace root, which is gitignored. Home directory items (`~/.claude`, `~/.serena`, `~/.m2`, `~/.claude.json`) are symlinks into this directory. This means configs and caches survive container restarts as long as the same host directory is mounted.
