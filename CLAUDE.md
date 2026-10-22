# CLAUDE.md

Containerized dev environment: Claude Code CLI + Serena agent on Ubuntu 26.04, with 13 domain-specific variants.

## Index

| File / Directory          | Contents (WHAT)                                                                                | Read When (WHEN)                                                              |
| ------------------------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `Dockerfile.base`         | Shared base image: Python, Node.js, Claude Code, Serena (pinned tag via SERENA_VERSION), cli-tools, sudoers, codeuser setup, managed Claude Code settings in /etc/claude-code, the check-tools.sh guard and base tool sheet | Modifying shared infrastructure, adding base packages, changing container-wide Claude Code defaults, bumping the Serena version |
| `Dockerfile.<variant>`    | 13 variant images: java, c, c-pico, x86, snes, 68k, image-dev, java-docker, java-angular, gowin, kicad, arduino, android (each FROM claude-env-base; the JDK-bearing variants java, java-docker, java-angular, x86, snes, 68k, kicad and android install it through `resources/snippets/shared/install-jdk.sh`, and the three java variants also use `install-jdtls.sh` and `install-lombok.sh`; x86, snes, 68k and android install Ghidra through `install-ghidra.sh`, x86, 68k and android install the REA MCP server through `install-rea.sh`, and snes pins and patches the 65816/SnesLoader modules, building SnesLoader on a throwaway JDK 21 that `install-jdk.sh` installs into a `target_dir` and the same RUN deletes); each stages its variant tool sheet and ends with a concat+check RUN; c, c-pico and arduino bake apt clangd for Serena | Modifying variant toolchains, changing variant-specific packages, bumping Ghidra or REA, the 65816 cspec patch |
| `Dockerfile.java-angular` | Fullstack Java + Angular variant: Java toolchain installed by the shared resources/snippets/shared/install-*.sh scripts with the x-java-toolchain pins (same as Dockerfile.java), variant-local Node 24 at /opt/node (PATH-shadows base apt Node), Angular CLI pinned via the java-angular service args in docker-compose.yml | Modifying the Angular CLI version, the Node version, the Java+Angular toolchain, or java-angular build steps |
| `Dockerfile.gowin`        | Gowin FPGA variant: OSS toolchain + Gowin EDA for Tang Nano 4K development                     | Modifying Gowin toolchain, EDA URL, USB rules                                 |
| `Dockerfile.arduino`      | Arduino Nano / AVR variant: apt arduino-cli + AVR toolchain + simavr; arduino:avr core pinned via the compose service arg and installed at build into /opt/arduino15 | Modifying the AVR toolchain, the core pin, or the serial access model |
| `Dockerfile.android`      | Android RE variant: JDK/Ghidra/REA via the shared scripts (REA with keep-frida), pinned JADX/Apktool/SDK/Frida/mitmproxy/blutter/Cpp2IL/Il2CppDumper downloads from the android service args, wrappers from resources/snippets/android | Modifying the Android toolchain, bumping an android pin, the frida/REA version assertion |
| `docker-compose.yml`      | Build orchestration: defines build args and image names for all 13 variants; shared x-java-toolchain version anchor (Java, JDT-LS and Lombok version+sha256 pins for java/java-docker/java-angular), x-ghidra-toolchain anchor (Ghidra version, date and sha256 for x86/snes/68k/android) and x-rea-toolchain anchor (REA_VERSION for x86/68k/android); java-angular-only pins (ANGULAR_CLI_VERSION, NODE_VERSION) live in its own service args, outside the anchor, arduino-only pin (ARDUINO_AVR_CORE_VERSION) likewise in its service args, kicad-only pins (FREEROUTING_VERSION, FREEROUTING_SHA256), android-only pins (JADX, Apktool, SDK, Frida, mitmproxy, blutter, Cpp2IL and Il2CppDumper versions and sha256) and snes-only pins (SNES_LOADER_REF, GHIDRA_65816_REF) in their service args | Building variants, understanding image naming convention, bumping Ghidra, REA or the SNES modules |
| `build.sh`                | Two-phase build: builds base image then all variants (or a single named variant); fails at check-tools.sh when a tool sheet and its Dockerfile disagree | Rebuilding images, changing build-time args                                    |
| `launch.sh`               | Variant-aware launcher: accepts variant as first arg, per-variant capability functions (mounts, serial/USB devices, rootless DinD, ports, the android host-adb mapping and blutter cache), usage-and-exit on an unknown variant, passes the first-launch verdict to the container as CLAUDE_JSON_MOUNTED | Changing startup behavior, bind mount configuration                      |
| `.gitignore`              | Excludes `.claudeproject/` (runtime state), `.ghidra-projects/` (snes), `.idea`, `.serena`, `.claude`, `.env` (the `.serena` pattern covers per-project Serena folders; Serena data lives under `.claudeproject/`) | Adding new gitignored paths                                          |
| `README.md`               | Architecture, design decisions, persistence model, authentication, variant reference           | Understanding architecture, design decisions, component relationships; editing the java-docker/gowin/kicad/arduino/x86-68k-android (REA, host adb) Troubleshooting entries or the java-angular launch caveats (mirrored in resources/tools notes) |
| `resources/`              | Config templates, shell scripts, variant-specific snippets and shared install scripts under snippets/shared, host-side udev rules, and `tools/` sheets and notes files baked into the image (eight notes files mirror prose in README.md or resources/snippets/snes; edit both) | Modifying Serena config, init sequence, variant Dockerfile resources, or USB device rules |

## Build & Run

```bash
# Build base image then all variant images
./build.sh [tag]

# Build base image then a single variant
./build.sh [tag] <variant>

# Launch a variant container with a host project mounted at /workspace
./launch.sh <variant> /path/to/your/project [tag]
```

Available variants: `java`, `c`, `c-pico`, `x86`, `snes`, `68k`, `image-dev`, `java-docker`, `java-angular`, `gowin`, `kicad`, `arduino`, `android`

Inside the container, `claude` starts a session with Serena pre-registered as an MCP tool. The Serena web dashboard is available at `http://localhost:24282/dashboard/`.

The android variant reaches devices through the host adb server: start it with `-L tcp:<docker0-ip>:5037` before a dynamic session (README android Troubleshooting).
