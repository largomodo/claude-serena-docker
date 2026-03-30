# Claude Code & Serena Environment

A containerized environment integrating Anthropic's **Claude Code** CLI with the **Serena** autonomous coding agent, configured for **x86 DOS and SNES ROM disassembly**.

This project provisions disassembly tools, architecture-specific wrappers, and authentication persistence automatically, eliminating environment drift between host and agent.

## Core Components

*   **Base:** Ubuntu 24.04 (Noble)
*   **Runtime:** OpenJDK 21 (Temurin, required by Ghidra) & Python 3 (managed via `uv`)
*   **Disassembly Tools:**
    *   **ndisasm** (NASM suite) — 16-bit linear disassembly via `dis16` wrapper
    *   **radare2** — interactive binary analysis via `r216` wrapper (16-bit mode)
    *   **objdump** — section/symbol dump via `dump16` wrapper (i8086 mode)
    *   **Ghidra 12.0.4 headless** (`analyzeHeadless`) — automated binary analysis with x86 real-mode and 65816 SNES processor support
    *   **snes-analyze** — single-command SNES ROM analysis wrapper (SNES loader + 65816 processor + register setup)
    *   **capstone** & **pefile** — Python libraries for scripted analysis
*   **Agent Stack:**
    *   **Claude Code:** CLI interface for Anthropic's models.
    *   **Serena:** Autonomous agent acting as an MCP (Model Context Protocol) server.

## Features

*   **16-bit Mode Enforcement:** Wrapper scripts (`dis16`, `r216`, `dump16`) apply correct 16-bit flags automatically. DOS binaries silently produce wrong output without them.
*   **SNES ROM Analysis:** The `snes-analyze` wrapper invokes Ghidra headless with the ViewtifulSlayer SNES loader, 65816 processor module, and `SetSnesRegisters.java` post-script in a single command. All SNES tooling is baked into the image at build time.
*   **Runtime Provisioning:** Automatically provisions configuration from remote repositories into `.claudeproject/` subdirectories, which are bind-mounted to their home directory counterparts at container start.
*   **Binary Detection:** Detects `.com`, `.exe`, `.asm`, `.sfc`, and `.smc` files on launch and logs architecture-specific tool recommendations.
*   **MCP Auto-Negotiation:** Automatically registers Serena as a tool provider for Claude Code upon container initialization.
*   **UID/GID Mapping:** Passthrough of host user permissions to prevent file ownership artifacts on the host filesystem.

## Usage

### 1. Build
Build the image using the host's UID/GID context:
```bash
./build.sh [optional_tag]
```

### 2. Launch
Mount a local project directory containing binaries or ROMs to the container's workspace:
```bash
./launch.sh /path/to/your/binary-project
```

Once inside the container, the environment is pre-initialized. You can interact via:
*   **Interactive Shell:** The container drops you into `bash`.
*   **Claude CLI:** Run `claude` to start a session. Serena is already registered as an MCP tool.
*   **x86 DOS Disassembly:** Use `dis16 <file.com>`, `r216 <file.exe>`, `dump16 <file.com>`, or `analyzeHeadless` with `-processor x86:LE:16:Real Mode:default`.
*   **SNES ROM Analysis:** Use `snes-analyze <file.sfc>` for single-command analysis, or `analyzeHeadless` directly. See `ghidra-snes-headless-usage.md` for full usage.

## Configuration & Persistence

Authentication tokens (Claude) and agent configurations are persisted in `.claudeproject/` at the root of your mounted project via Docker bind mounts. On first launch, `.claude.json` is captured via an EXIT trap when the session ends; on subsequent launches it is bind-mounted directly.

> **Note:** Running multiple containers against the same workspace directory simultaneously is not supported. Concurrent bind mounts to the same `.claudeproject/` directory can corrupt state (git operations, `.claude.json` writes).

For detailed configuration logic, prompts, and global settings used by the provisioning script, refer to:
*   **[largomodo/claude-config](https://github.com/largomodo/claude-config)**
    *   *Forked from: [solatis/claude-config](https://github.com/solatis/claude-config)*
*   **[oraios/serena](https://github.com/oraios/serena)**

To customize the agent's behavior, modify the `.serena/serena_config.yml` that is generated in your project root after the first run.
