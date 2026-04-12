# CLAUDE.md

Containerized dev environment: Claude Code CLI + Serena agent + Java LSP (JDTLS) on Ubuntu 24.04.

## Index

| File / Directory | Contents (WHAT)                                                                 | Read When (WHEN)                                                              |
| ---------------- | ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `Dockerfile`     | Image definition: JDK, JDTLS, Node.js, Maven, Claude Code CLI, Serena installs | Modifying base image, adding packages, changing install order                 |
| `build.sh`       | Image build script; passes host UID/GID as build args                           | Rebuilding the image, changing build-time args                                |
| `launch.sh`      | Container launch; host-side directory prep, bind mount args, docker run         | Changing startup behavior, bind mount configuration                           |
| `.gitignore`     | Excludes `.env` (secrets) and `.claudeproject/` (runtime state)                 | Adding new gitignored paths                                                   |
| `README.md`      | Architecture, design decisions, persistence model, authentication               | Understanding architecture, design decisions, component relationships         |
| `resources/`     | Config templates and shell scripts baked into the image                          | Modifying Serena config, JDTLS launcher, or container init sequence           |

## Build & Run

```bash
# Build the Docker image (uses host UID/GID for permission mapping)
./build.sh [optional_tag]

# Launch container with a host project mounted at /workspace
./launch.sh /path/to/your/java-project [optional_tag]
```

Inside the container, `claude` starts a session with Serena pre-registered as an MCP tool. The Serena web dashboard is available at `http://localhost:24282/dashboard/`.
