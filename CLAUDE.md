# CLAUDE.md

Containerized dev environment: Claude Code CLI + Serena agent + C/C++ LSP (clangd, auto-managed) + Raspberry Pi Pico toolchain on Ubuntu 25.10.

## Index

| File / Directory                     | Contents (WHAT)                                                                 | Read When (WHEN)                                             |
| ------------------------------------ | ------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `Dockerfile`                         | Image definition: build-essential, Node.js, Claude Code CLI, Serena, Pico toolchain installs | Modifying base image, adding packages, changing install order, changing Pico SDK/toolchain versions |
| `build.sh`                           | Image build script; passes host UID/GID as build args                           | Rebuilding the image, changing build-time args               |
| `launch.sh`                          | Container launch; host-side directory preparation, conditional .claude.json detection, bind mount arguments, USB cgroup rules, docker run invocation | Changing startup behavior, bind mount configuration, USB passthrough |
| `.gitignore`                         | Excludes `.env` (secrets) and `.claudeproject/` (runtime state)                 | Adding new gitignored paths                                  |
| `README.md`                          | Architecture, design decisions, Pico toolchain rationale, authentication, persistence model, container lifecycle | Understanding architecture, invisible knowledge, design decisions |
| `resources/config/serena_config.yml` | Serena config template: LSP backend, dashboard port, tool timeout               | Changing Serena behavior, dashboard address, tool timeout    |
| `resources/scripts/init-workspace.sh`| ENTRYPOINT: populates bind-mounted directories, session-exit .claude.json persistence, Serena indexing, MCP registration | Debugging container startup, changing init sequence |

## Build & Run

```bash
# Build the Docker image (uses host UID/GID for permission mapping)
./build.sh [optional_tag]

# Launch container with a host project mounted at /workspace
./launch.sh /path/to/your/project [optional_tag]
```

Inside the container, `claude` starts a session with Serena pre-registered as an MCP tool. The Serena web dashboard is available at `http://localhost:24282/dashboard/`.

