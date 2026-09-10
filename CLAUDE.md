# CLAUDE.md

Containerized dev environment: Claude Code CLI + Serena agent on Ubuntu 26.04, with 11 domain-specific variants.

## Index

| File / Directory          | Contents (WHAT)                                                                                | Read When (WHEN)                                                              |
| ------------------------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `Dockerfile.base`         | Shared base image: Python, Node.js, Claude Code, Serena, cli-tools, sudoers, codeuser setup, managed Claude Code settings in /etc/claude-code | Modifying shared infrastructure, adding base packages, changing container-wide Claude Code defaults |
| `Dockerfile.<variant>`    | 11 variant images: java, c, c-pico, x86, snes, 68k, image-dev, java-docker, java-angular, gowin, kicad (each FROM claude-env-base) | Modifying variant toolchains, changing variant-specific packages             |
| `Dockerfile.java-angular` | Fullstack Java + Angular variant: Java toolchain block duplicated from Dockerfile.java, variant-local Node 24 at /opt/node (PATH-shadows base apt Node), Angular CLI pinned via the java-angular service args in docker-compose.yml | Modifying the Angular CLI version, the Node version, the Java+Angular toolchain, or java-angular build steps |
| `Dockerfile.gowin`        | Gowin FPGA variant: OSS toolchain + Gowin EDA for Tang Nano 4K development                     | Modifying Gowin toolchain, EDA URL, USB rules                                 |
| `docker-compose.yml`      | Build orchestration: defines build args and image names for all 11 variants; shared x-java-toolchain version anchor (Java pins for java/java-docker/java-angular); java-angular-only pins (ANGULAR_CLI_VERSION, NODE_VERSION) live in its own service args, outside the anchor | Building variants, understanding image naming convention                       |
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

Available variants: `java`, `c`, `c-pico`, `x86`, `snes`, `68k`, `image-dev`, `java-docker`, `java-angular`, `gowin`, `kicad`

Inside the container, `claude` starts a session with Serena pre-registered as an MCP tool. The Serena web dashboard is available at `http://localhost:24282/dashboard/`.
