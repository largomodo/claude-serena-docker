# Claude Code & Serena Environment

A containerized development environment integrating Anthropic's **Claude Code** CLI with the **Serena** autonomous coding agent, optimized for Java development via LSP.

This project orchestrates an ephemeral runtime that provisions tool configuration, language servers, and authentication persistence automatically, eliminating environment drift between host and agent.

## Core Components

*   **Base:** Ubuntu 24.04 (Noble)
*   **Runtime:** OpenJDK 25 (Temurin) & Python 3 (managed via `uv`)
*   **LSP:** Eclipse JDT Language Server (JDTLS) for deep Java static analysis.
*   **Agent Stack:**
    *   **Claude Code:** CLI interface for Anthropic's models.
    *   **Serena:** Autonomous agent acting as an MCP (Model Context Protocol) server.

## Features

*   **Runtime Provisioning:** Automatically clones and symlinks configuration from remote repositories into a persistent `.claudeproject` directory within the mounted workspace.
*   **Auto-Discovery:** Detects Java source files on launch and initializes the Serena project index and JDTLS workspace.
*   **MCP Auto-Negotiation:** Automatically registers Serena as a tool provider for Claude Code upon container initialization.
*   **UID/GID Mapping:** Passthrough of host user permissions to prevent file ownership artifacts on the host filesystem.

## Usage

### 1. Build
Build the image using the host's UID/GID context:
```bash
./build.sh [optional_tag]
```

### 2. Launch
Mount a local project directory to the container's workspace:
```bash
./launch.sh /path/to/your/java-project
```

Once inside the container, the environment is pre-initialized. You can interact via:
*   **Interactive Shell:** The container drops you into `bash`.
*   **Claude CLI:** Run `claude` to start a session. Serena is already registered as an MCP tool.

## Configuration & Persistence

Authentication tokens (Claude) and agent configurations are persisted in the `.claudeproject` directory at the root of your mounted project.

For detailed configuration logic, prompts, and global settings used by the provisioning script, refer to:
*   **[largomodo/claude-config](https://github.com/largomodo/claude-config)**
    *   *Forked from: [solatis/claude-config](https://github.com/solatis/claude-config)*
* ** [oraios/serena](https://github.com/oraios/serena)**

To customize the agent's behavior, modify the `.serena/serena_config.yml` that is generated in your project root after the first run.
