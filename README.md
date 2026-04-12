# Claude Code & Serena Environment

A containerized development environment integrating Anthropic's **Claude Code** CLI with the **Serena** autonomous coding agent, with language support for Java, Python, Go, Rust, and TypeScript via LSP.

This project orchestrates an ephemeral runtime that provisions tool configuration, language servers, and authentication persistence automatically, eliminating environment drift between host and agent.

## Prerequisites

*   **Docker** (tested with Docker Engine 24+; Docker Desktop also works)
*   **Internet access** at container startup — the init script clones configuration from GitHub (`largomodo/claude-config`) on first launch and pulls updates on subsequent launches
*   **Anthropic API credentials** — see [Authentication](#authentication) below

## Core Components

*   **Base:** Ubuntu 24.04 (Noble)
*   **Runtime:** OpenJDK 21 (Temurin) & Python 3 (managed via `uv`)
*   **LSP:** Eclipse JDT Language Server (JDTLS) for deep Java static analysis.
*   **Agent Stack:**
    *   **Claude Code:** CLI interface for Anthropic's models.
    *   **Serena:** Autonomous agent acting as an MCP (Model Context Protocol) server.

## Usage

### 1. Authentication

Create a `.env` file in the project root (it is gitignored):

```bash
# .env
CLAUDE_CODE_OAUTH_TOKEN=your-token-here
```

`launch.sh` sources this file and passes the token into the container. You can also export the variable in your shell — shell-exported values take precedence over `.env`.

If no token is provided, Claude Code will prompt for interactive authentication on first launch.

### 2. Build
Build the image using the host's UID/GID context:
```bash
./build.sh [optional_tag]
```

### 3. Launch
Mount a local project directory to the container's workspace:
```bash
./launch.sh /path/to/your/project [optional_tag]
```

On startup, the container:
1. Pulls Claude Code configuration from GitHub
2. Configures Serena with sensible defaults
3. Auto-detects your project language (Java, Python, Go, Rust, or TypeScript) and indexes it
4. Registers Serena as a Claude Code MCP tool

Once ready, you can interact via:
*   **Interactive Shell:** The container drops you into `bash`.
*   **Claude CLI:** Run `claude` to start a session. Serena is already registered as an MCP tool.

The Serena web dashboard is available at `http://localhost:24282/dashboard/`.

> **Important:** Inside the container, `claude` is aliased to `claude --dangerously-skip-permissions`, which skips all tool permission prompts. This is intentional for unattended agent workflows but means Claude Code will execute file edits, shell commands, and other tools without asking for confirmation.

> **Important:** Always stop the container with `docker stop`, not `docker kill`. On first launch, session credentials are saved via an EXIT trap that only fires on graceful shutdown. Using `docker kill` (SIGKILL) bypasses the trap and your credentials won't be persisted.

> **Note:** Running multiple containers against the same workspace directory simultaneously is not supported. Concurrent bind mounts to the same `.claudeproject/` directory can corrupt state.

## Supported Languages

The container auto-detects source files on startup and initializes the Serena project index. Detection uses first-match-wins — in a multi-language project, only the first detected language is indexed.

Detection order: **Java** → **Python** → **Go** → **Rust** → **TypeScript**

If no source files are detected, or you need a different language than the one auto-detected, create the project manually:
```bash
serena project create --language <lang> --index
```
> **Note:** For Java projects, if indexing fails with a timeout error on first use, run `serena project index` again — JDTLS requires a warm-up period and typically succeeds on the second or third attempt.

## Persistence

All mutable state lives in `.claudeproject/` at the workspace root (gitignored). Configs, credentials, and caches survive container restarts as long as the same host directory is mounted.

What is persisted:
- **Claude Code config** (`~/.claude/`) — settings, prompts, MCP registrations
- **Serena config** (`~/.serena/`) — Serena configuration and project data
- **Maven cache** (`~/.m2/`) — downloaded dependencies
- **Shell history** (`~/.bash_history`)
- **Claude Code credentials** (`~/.claude.json`) — API tokens and onboarding state

## Troubleshooting

**Serena tools don't appear in Claude Code**
The MCP registration runs automatically but suppresses errors. Run the command manually:
```bash
claude mcp add serena -- serena start-mcp-server --context ide-assistant --project /workspace
```

**Indexing is slow or fails on first launch (Java projects)**
JDTLS has a cold-start issue where its initial startup exceeds Serena's 10-second LSP timeout. The init script retries up to 3 times with 5-second delays between attempts. The first successful index typically requires at least two attempts; actual time depends on project size and host performance.

**Credentials not saved after first session**
This happens if the container was killed with `docker kill` instead of `docker stop`. Re-launch and complete the onboarding flow again, then exit normally or use `docker stop`.

**Config clone fails on first launch (container exits)**
The container needs to reach `github.com` to clone configuration on first launch. If the clone fails, the container exits. Configure Docker's proxy settings or pre-populate `.claudeproject/.claude/` with your config files before launching.

**Config update warns on subsequent launches (non-fatal)**
On subsequent launches, the init script runs `git pull` to update config. If this fails (e.g., network unavailable), the container continues with the previously cloned config and prints a warning.

## Architecture

For contributors and maintainers — details on how the container works internally.

### Key Directories

- `/workspace` — mounted host project directory (container working directory)
- `/workspace/.claudeproject/` — persisted configs, auth tokens, Maven cache (gitignored)
- `/home/codeuser/serena/` — Serena installation (`$SERENA_HOME`)
- `/opt/cli-tools/.venv/` — isolated Python venv for CLI tools (httpie, yq, csvkit, litecli, pgcli); separate from Serena's venv to avoid dependency conflicts
- `/opt/jdtls/` — Eclipse JDT Language Server installation
- `/opt/java/openjdk/` — JDK installation (`$JAVA_HOME`)
- `/usr/local/share/claude-env/` — immutable config templates baked into image

### Container Lifecycle

1. **Build time** (`Dockerfile`): Installs JDK, JDTLS, Node.js, Maven, Claude Code CLI, and Serena. Copies golden-master configs to `/usr/local/share/claude-env/`.
2. **Runtime entry** (`resources/scripts/init-workspace.sh`): The ENTRYPOINT script provisions bind-mounted directories, clones/updates Claude config, copies Serena config templates, auto-detects project language, indexes via Serena, and registers the MCP server.
3. **Interactive session**: Drops into bash; user runs `claude` to start AI-assisted coding.

### Persistence Implementation

`launch.sh` pre-creates `.claudeproject/.claude`, `.claudeproject/.serena`, and `.claudeproject/.m2` on the host and bind-mounts them to their `~/` counterparts, so changes inside the container persist directly to the host.

`.claude.json` uses two-mode persistence:
- **Consecutive launch:** `launch.sh` detects `"hasCompletedOnboarding": true` in `.claudeproject/.claude.json` and bind-mounts it to `~/.claude.json`.
- **First launch:** No `.claude.json` exists yet. An EXIT trap copies `~/.claude.json` to `.claudeproject/.claude.json` when the session ends.

### Configuration

- **Serena config template**: `resources/config/serena_config.yml` — LSP backend, web dashboard on `0.0.0.0:24282` (default Serena port; listen address configured in the yml), 240s tool timeout, JDTLS workspace at `/workspace/.jdtls-workspace`
- **JDTLS launcher**: `resources/scripts/jdtls.sh` — accepts `--workspace=` arg, 2G max heap
- **Claude config**: Pulled from `github.com/largomodo/claude-config` (fork of `solatis/claude-config`)

### CLI Tool Tiers

Tools are split into three tiers based on image size constraints (target: <5GB) and usage frequency.

**Tier 1 — System utilities (baked in via apt):**
poppler-utils (needed for programmatic text extraction via pdftotext/grep; Claude Code's native PDF reading is visual-only), pandoc, sqlite3, graphviz, tesseract-ocr, shellcheck, ripgrep, fd-find, tree, unzip/zip/xz-utils, file, less, man-db, postgresql-client, imagemagick, ffmpeg, net-tools, dnsutils, iputils-ping, traceroute, strace, htop, ncdu. Note: `build-essential` in the base apt layer already provides gcc, g++, make — do not add them here.

**Tier 2 — Python CLI tools (baked in via uv, `/opt/cli-tools/.venv`):**
httpie (`http`), yq, csvkit, litecli, pgcli.

These are installed in a dedicated venv separate from Serena's `~/serena/.venv` to prevent dependency conflicts. The venv bin directory is prepended to `PATH` so tools are available without activation.

> **Note:** For Java projects, the Gradle wrapper (`gradlew`) is the recommended build approach. A specific Gradle version is not baked into the image to avoid version mismatch with the wrapper's declared version.

## External References

*   **[largomodo/claude-config](https://github.com/largomodo/claude-config)** — Claude Code settings and prompts (forked from [solatis/claude-config](https://github.com/solatis/claude-config))
*   **[oraios/serena](https://github.com/oraios/serena)** — Serena autonomous coding agent
