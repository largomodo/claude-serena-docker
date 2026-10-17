# CLAUDE.md

Containerized dev environment: Claude Code CLI + Serena agent on Ubuntu 26.04, with 12 domain-specific variants.

## Index

| File / Directory          | Contents (WHAT)                                                                                | Read When (WHEN)                                                              |
| ------------------------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `Dockerfile.base`         | Shared base image: Python, Node.js, Claude Code, Serena (pinned tag via SERENA_VERSION), cli-tools, sudoers, codeuser setup, managed Claude Code settings in /etc/claude-code, the check-tools.sh guard and base tool sheet | Modifying shared infrastructure, adding base packages, changing container-wide Claude Code defaults, bumping the Serena version |
| `Dockerfile.<variant>`    | 12 variant images: java, c, c-pico, x86, snes, 68k, image-dev, java-docker, java-angular, gowin, kicad, arduino (each FROM claude-env-base; the JDK-bearing variants java, java-docker, java-angular, x86, snes and kicad install it through `resources/snippets/shared/install-jdk.sh`, and the three java variants also use `install-jdtls.sh` and `install-lombok.sh`); each stages its variant tool sheet and ends with a concat+check RUN; c, c-pico and arduino bake apt clangd for Serena | Modifying variant toolchains, changing variant-specific packages             |
| `Dockerfile.java-angular` | Fullstack Java + Angular variant: Java toolchain installed by the shared resources/snippets/shared/install-*.sh scripts with the x-java-toolchain pins (same as Dockerfile.java), variant-local Node 24 at /opt/node (PATH-shadows base apt Node), Angular CLI pinned via the java-angular service args in docker-compose.yml | Modifying the Angular CLI version, the Node version, the Java+Angular toolchain, or java-angular build steps |
| `Dockerfile.gowin`        | Gowin FPGA variant: OSS toolchain + Gowin EDA for Tang Nano 4K development                     | Modifying Gowin toolchain, EDA URL, USB rules                                 |
| `Dockerfile.arduino`      | Arduino Nano / AVR variant: apt arduino-cli + AVR toolchain + simavr; arduino:avr core pinned via the compose service arg and installed at build into /opt/arduino15 | Modifying the AVR toolchain, the core pin, or the serial access model |
| `docker-compose.yml`      | Build orchestration: defines build args and image names for all 12 variants; shared x-java-toolchain version anchor (Java, JDT-LS and Lombok version+sha256 pins for java/java-docker/java-angular); java-angular-only pins (ANGULAR_CLI_VERSION, NODE_VERSION) live in its own service args, outside the anchor, arduino-only pin (ARDUINO_AVR_CORE_VERSION) likewise in its service args, kicad-only pins (FREEROUTING_VERSION, FREEROUTING_SHA256) in its service args | Building variants, understanding image naming convention                       |
| `build.sh`                | Two-phase build: builds base image then all variants (or a single named variant); fails at check-tools.sh when a tool sheet and its Dockerfile disagree | Rebuilding images, changing build-time args                                    |
| `launch.sh`               | Variant-aware launcher: accepts variant as first arg, per-variant capability functions (mounts, serial/USB devices, rootless DinD, ports), usage-and-exit on an unknown variant, passes the first-launch verdict to the container as CLAUDE_JSON_MOUNTED | Changing startup behavior, bind mount configuration                      |
| `.gitignore`              | Excludes `.claudeproject/` (runtime state), `.ghidra-projects/` (snes), `.idea`, `.serena`, `.claude`, `.env` (the `.serena` pattern covers per-project Serena folders; Serena data lives under `.claudeproject/`) | Adding new gitignored paths                                          |
| `README.md`               | Architecture, design decisions, persistence model, authentication, variant reference           | Understanding architecture, design decisions, component relationships; editing the java-docker/gowin/kicad/arduino Troubleshooting entries or the java-angular launch caveats (mirrored in resources/tools notes) |
| `resources/`              | Config templates, shell scripts, variant-specific snippets and shared install scripts under snippets/shared, host-side udev rules, and `tools/` sheets and notes files baked into the image (six notes files mirror prose in README.md or resources/snippets/snes; edit both) | Modifying Serena config, init sequence, variant Dockerfile resources, or USB device rules |

## Build & Run

```bash
# Build base image then all variant images
./build.sh [tag]

# Build base image then a single variant
./build.sh [tag] <variant>

# Launch a variant container with a host project mounted at /workspace
./launch.sh <variant> /path/to/your/project [tag]
```

Available variants: `java`, `c`, `c-pico`, `x86`, `snes`, `68k`, `image-dev`, `java-docker`, `java-angular`, `gowin`, `kicad`, `arduino`

Inside the container, `claude` starts a session with Serena pre-registered as an MCP tool. The Serena web dashboard is available at `http://localhost:24282/dashboard/`.
