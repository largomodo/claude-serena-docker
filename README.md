# Claude Code & Serena Environment — Neo Geo Diag BIOS

A containerized development environment integrating Anthropic's **Claude Code** CLI with the **Serena** autonomous coding agent, configured with the **VASM/VLINK** toolchain for building the [neogeo-diag-bios](https://github.com/jwestfall69/neogeo-diag-bios).

This project orchestrates an ephemeral runtime that provisions tool configuration, assembler/linker toolchains, and authentication persistence automatically, eliminating environment drift between host and agent.

## Core Components

*   **Base:** Ubuntu 24.04 (Noble)
*   **Toolchain:** VASM (m68k + z80 Motorola syntax) & VLINK (portable linker), compiled from source
*   **Runtime:** Python 3 (managed via `uv`)
*   **Agent Stack:**
    *   **Claude Code:** CLI interface for Anthropic's models.
    *   **Serena:** Autonomous agent acting as an MCP (Model Context Protocol) server.

## Features

*   **Neo Geo Build Toolchain:** VASM assembler (both `vasmm68k_mot` and `vasmz80_mot` flavors) and VLINK linker pre-built and available on `$PATH`.
*   **Runtime Provisioning:** Automatically provisions configuration from remote repositories into `.claudeproject/` subdirectories, which are bind-mounted to their home directory counterparts at container start.
*   **Auto-Discovery:** Detects source files on launch (ASM, Python, Go, Rust, TypeScript) and initializes the Serena project index.
*   **MCP Auto-Negotiation:** Automatically registers Serena as a tool provider for Claude Code upon container initialization.
*   **UID/GID Mapping:** Passthrough of host user permissions to prevent file ownership artifacts on the host filesystem.

## Usage

### 1. Build
Build the image using the host's UID/GID context:
```bash
./build.sh [optional_tag]
```

### 2. Launch
Mount the neogeo-diag-bios source directory to the container's workspace:
```bash
./launch.sh /path/to/neogeo-diag-bios
```

### 3. Compile the BIOS
Inside the container:
```bash
# Build SP1 (68k System BIOS)
cd sp1 && make

# Build M1 (Z80 Sound Driver)
cd m1 && make
```

### 4. Verify
Confirm the following artifacts exist:
- `sp1/output/sp1.bin` — System BIOS
- `m1/output/m1.bin` — Z80 Sound Driver
- `sp1/gen-crc-mirror` — Helper binary
- `m1/gen-crc-mirror-bank` — Helper binary

### 5. AI-Assisted Development
Once inside the container, the environment is pre-initialized. You can interact via:
*   **Interactive Shell:** The container drops you into `bash`.
*   **Claude CLI:** Run `claude` to start a session. Serena is already registered as an MCP tool.

## Configuration & Persistence

Authentication tokens (Claude) and agent configurations are persisted in `.claudeproject/` at the root of your mounted project via Docker bind mounts. On first launch, `.claude.json` is captured via an EXIT trap when the session ends; on subsequent launches it is bind-mounted directly.

> **Note:** Running multiple containers against the same workspace directory simultaneously is not supported. Concurrent bind mounts to the same `.claudeproject/` directory can corrupt state (git operations, `.claude.json` writes).

For detailed configuration logic, prompts, and global settings used by the provisioning script, refer to:
*   **[largomodo/claude-config](https://github.com/largomodo/claude-config)**
    *   *Forked from: [solatis/claude-config](https://github.com/solatis/claude-config)*
*   **[oraios/serena](https://github.com/oraios/serena)**
*   **[jwestfall69/neogeo-diag-bios](https://github.com/jwestfall69/neogeo-diag-bios)**

To customize the agent's behavior, modify the `.serena/serena_config.yml` that is generated in your project root after the first run.
