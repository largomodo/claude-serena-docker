# CLAUDE.md

Containerized dev environment: Claude Code CLI + Serena agent on Ubuntu 26.04, with 8 domain-specific variants.

## Index

| File / Directory          | Contents (WHAT)                                                                                | Read When (WHEN)                                                              |
| ------------------------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `Dockerfile.base`         | Shared base image: Python, Node.js, Claude Code, Serena, cli-tools, sudoers, codeuser setup   | Modifying shared infrastructure, adding base packages                         |
| `Dockerfile.<variant>`    | 8 variant images: java, c, c-pico, x86, snes, 68k, image-dev, gowin (each FROM claude-env-base) | Modifying variant toolchains, changing variant-specific packages             |
| `Dockerfile.gowin`        | Gowin FPGA variant: OSS toolchain + Gowin EDA for Tang Nano 4K development                     | Modifying Gowin toolchain, EDA URL, USB rules                                 |
| `docker-compose.yml`      | Build orchestration: defines build args and image names for all 8 variants                     | Building variants, understanding image naming convention                       |
| `build.sh`                | Two-phase build: builds base image then all variants (or a single named variant)               | Rebuilding images, changing build-time args                                    |
| `launch.sh`               | Variant-aware launcher: accepts variant as first arg, handles conditional mounts and USB passthrough | Changing startup behavior, bind mount configuration                      |
| `.gitignore`              | Excludes `.claudeproject/` (runtime state), `.ghidra-projects/` (snes), `.idea`, `.serena`, `.claude`, `.env` | Adding new gitignored paths                                          |
| `README.md`               | Architecture, design decisions, persistence model, authentication, variant reference           | Understanding architecture, design decisions, component relationships          |
| `resources/`              | Config templates, shell scripts, variant-specific snippets, and host-side udev rules baked into the image | Modifying Serena config, init sequence, variant Dockerfile resources, or USB device rules |

## Build & Run

```bash
# Build base image then all variant images
./build.sh [tag]

# Build base image then a single variant
./build.sh [tag] <variant>

# Launch a variant container with a host project mounted at /workspace
./launch.sh <variant> /path/to/your/project [tag]
```

Available variants: `java`, `c`, `c-pico`, `x86`, `snes`, `68k`, `image-dev`, `gowin`

Inside the container, `claude` starts a session with Serena pre-registered as an MCP tool. The Serena web dashboard is available at `http://localhost:24282/dashboard/`.
