# CLAUDE.md

Containerized dev environment: Claude Code CLI + Serena agent on Ubuntu 26.04, with 6 domain-specific variants.

## Index

| File / Directory          | Contents (WHAT)                                                                                | Read When (WHEN)                                                              |
| ------------------------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `Dockerfile.base`         | Shared base image: Python, Node.js, Claude Code, Serena, cli-tools, sudoers, codeuser setup   | Modifying shared infrastructure, adding base packages                         |
| `Dockerfile.<variant>`    | 6 variant images: java, c, c-pico, x86, snes, 68k (each FROM claude-env-base)                 | Modifying variant toolchains, changing variant-specific packages               |
| `docker-compose.yml`      | Build orchestration: defines build args and image names for all 6 variants                     | Building variants, understanding image naming convention                       |
| `build.sh`                | Two-phase build: builds base image then all variants (or a single named variant)               | Rebuilding images, changing build-time args                                    |
| `launch.sh`               | Variant-aware launcher: accepts variant as first arg, handles conditional mounts and USB passthrough | Changing startup behavior, bind mount configuration                      |
| `.gitignore`              | Excludes `.claudeproject/` (runtime state), `.ghidra-projects/` (snes), `.idea`, `.serena`, `.claude` | Adding new gitignored paths                                          |
| `README.md`               | Architecture, design decisions, persistence model, authentication, variant reference           | Understanding architecture, design decisions, component relationships          |
| `resources/`              | Config templates, shell scripts, and variant-specific snippets baked into the image            | Modifying Serena config, init sequence, or variant Dockerfile resources        |

## Build & Run

```bash
# Build base image then all variant images
./build.sh [tag]

# Build base image then a single variant
./build.sh [tag] <variant>

# Launch a variant container with a host project mounted at /workspace
./launch.sh <variant> /path/to/your/project [tag]
```

Available variants: `java`, `c`, `c-pico`, `x86`, `snes`, `68k`

Inside the container, `claude` starts a session with Serena pre-registered as an MCP tool. The Serena web dashboard is available at `http://localhost:24282/dashboard/`.
