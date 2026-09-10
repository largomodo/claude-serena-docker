# Claude Code & Serena Environment

A containerized development environment integrating Anthropic's **Claude Code** CLI with the **Serena** autonomous coding agent, supporting 11 domain-specific variants.

This project orchestrates an ephemeral runtime that provisions tool configuration, language servers, and authentication persistence automatically, eliminating environment drift between host and agent.

## Prerequisites

*   **Docker** (tested with Docker Engine 24+; Docker Desktop also works)
*   **Internet access** at container startup — the init script clones configuration from GitHub (`largomodo/claude-config`) on first launch and pulls updates on subsequent launches
*   **Anthropic API credentials** — see [Authentication](#authentication) below

## Core Components

*   **Base:** Ubuntu 26.04
*   **Runtime:** Python 3 (managed via `uv`); OpenJDK 21 (Temurin) in java/x86/snes variants
*   **Agent Stack:**
    *   **Claude Code:** CLI interface for Anthropic's models.
    *   **Serena:** Autonomous agent acting as an MCP (Model Context Protocol) server.

## Variants

| Variant   | Domain                      | Language Detection Priority          | Extra Toolchain                          |
| --------- | --------------------------- | ------------------------------------ | ---------------------------------------- |
| `java`    | Java development            | Java → Python → Go → Rust → TS       | JDK 21, JDTLS, Maven                    |
| `c`       | C/C++ development           | C/C++ → Python → Go → Rust → TS      | clangd (auto-managed by Serena)          |
| `c-pico`  | Raspberry Pi Pico firmware  | C/C++ → Python → Go → Rust → TS      | Pico SDK, RISC-V toolchain, picotool, OpenOCD |
| `x86`     | x86/DOS binary analysis     | Binary (com/exe/asm) — no Serena project | Ghidra 12.0.4, nasm, radare2, capstone |
| `snes`    | SNES ROM analysis           | Binary (sfc/smc/asm) — no Serena project | Ghidra 12.0.4 + SNES loader, nasm, radare2 |
| `68k`     | 68000/Neo Geo development   | asm → Python → Go → Rust → TS        | MAME, VASM, VLINK                        |
| `image-dev` | Variant dev and testing     | Python → Go → Rust → TS              | Docker Engine, docker compose, rootless DinD |
| `java-docker` | Java development + container workflows | Java → Python → Go → Rust → TS | JDK 21, JDTLS, Maven, Docker Engine, docker compose, rootless DinD |
| `java-angular` | Fullstack Java + Angular | Java → Angular → TS → Python (polyglot: all detected are indexed) | JDK 21, JDTLS, Maven, Angular CLI (variant-local Node 24 at /opt/node) |
| `gowin`   | Gowin FPGA development      | Python (no Verilog LSP)              | Gowin EDA, Yosys, nextpnr, Apicula, openFPGALoader, iVerilog, Verilator, GHDL |
| `kicad`   | KiCad PCB/EDA design        | Python (no KiCad LSP)                | KiCad 9, KiCAD-MCP-Server (headless SWIG backend) |

## Usage

### 1. Authentication

Create a `.env` file in the project root (it is gitignored):

```bash
# .env
CLAUDE_CODE_OAUTH_TOKEN=your-token-here
```

`launch.sh` sources this file and passes the token into the container. You can also export the variable in your shell — shell-exported values take precedence over `.env`.

If no token is provided, Claude Code will prompt for interactive authentication on first launch.

### 2. Build
Build the image using the host's UID/GID context:
```bash
# Build base image then all 11 variants
./build.sh [tag]

# Build base image then a single variant
./build.sh [tag] <variant>
```

> **Note:** Java/JDT-LS versions are pinned once in `docker-compose.yml` (the `x-java-toolchain` anchor) for all three Java-bearing variants (`java`, `java-docker`, `java-angular`). Building these Dockerfiles directly with `docker build` fails the toolchain guard; use `./build.sh` (compose-driven), which supplies the required values.

> **Note:** The java-angular variant also pins `NODE_VERSION` and `ANGULAR_CLI_VERSION` in its own service args (outside the shared anchor); a bare `docker build` on `Dockerfile.java-angular` fails those guards too.

### 3. Launch
Mount a local project directory to the container's workspace:
```bash
./launch.sh <variant> /path/to/your/project [tag]
```

On startup, the container:
1. Pulls Claude Code configuration from GitHub
2. Configures Serena with sensible defaults
3. Auto-detects your project language (varies by variant) and indexes it
4. Registers Serena as a Claude Code MCP tool

Once ready, you can interact via:
*   **Interactive Shell:** The container drops you into `bash`.
*   **Claude CLI:** Run `claude` to start a session. Serena is already registered as an MCP tool.

The Serena web dashboard is available at `http://localhost:24282/dashboard/`.

> **Important:** Inside the container, `claude` is aliased to `claude --dangerously-skip-permissions`, which skips all tool permission prompts. This is intentional for unattended agent workflows but means Claude Code will execute file edits, shell commands, and other tools without asking for confirmation.

> **Important:** Always stop the container with `docker stop`, not `docker kill`. On first launch, session credentials are saved via an EXIT trap that only fires on graceful shutdown. Using `docker kill` (SIGKILL) bypasses the trap and your credentials won't be persisted.

> **Note:** Running multiple containers against the same workspace directory simultaneously is not supported. Concurrent bind mounts to the same `.claudeproject/` directory can corrupt state.

> **Note:** The java-docker variant publishes fixed host ports `8080` and `5005` (Quarkus dev mode and the Java debugger). Running two java-docker instances at once on the same host causes a port collision on launch; only one instance can bind these ports at a time.

> **Note:** The java-angular variant has several fullstack-specific caveats:
> - `ng serve` must bind all interfaces to be reachable through the published port — use `ng serve --host 0.0.0.0`, or set `host` in `angular.json`. The dev server isn't hardened; this is fine for a local container.
> - For a backend proxy, use a `proxy.conf.json` mapping `/api` to `http://localhost:8080` via `ng serve --proxy-config proxy.conf.json`, giving a single origin with no CORS needed in dev.
> - Unit tests are headless by construction (Vitest + jsdom). If a scaffold produces Karma, migrate to the Vitest builder rather than installing a browser.
> - Real-browser e2e is a per-project Chrome apt-repo escape hatch, not baked into the image.
> - Serena creates the project with `languages: [java, angular]`, and the Angular LS silently degrades until `npm ci` has run — the init script only warns, it never runs `npm ci` itself.
> - Fixed host ports `4200`/`8080`/`5005` collide across concurrent instances (same tradeoff as java-docker).
> - The global Angular CLI major and a full Node version are pinned in the java-angular service args in `docker-compose.yml`; this variant's Node (at `/opt/node`) shadows the base image's apt Node via PATH while all other variants keep apt Node. Check https://angular.dev/reference/versions before bumping either pin, and keep `NODE_VERSION` inside the pinned Angular major's supported range.
> - Run `which node` / `which ng` inside the container to confirm resolution against `/opt/node` — `/usr/bin/node` (apt Node) remains installed but unreferenced.
> - `/opt/node` is root-owned. For a runtime global npm install, use the absolute path `sudo /opt/node/bin/npm install -g <pkg>` — a bare `sudo npm install -g` silently resolves the apt npm at `/usr/bin/npm` instead, because the codeuser sudoers entry has no `secure_path` override and sudo falls back to Ubuntu's default, which excludes `/opt/node/bin`.

## Supported Languages

Each variant auto-detects source files on startup and initializes the Serena project index. Detection uses first-match-wins — in a multi-language project, only the first detected language is indexed. Binary analysis variants (x86, snes) skip Serena project creation. The java-angular variant is an exception: it collects every detected language into one polyglot Serena project instead of stopping at the first match.

Detection order varies by variant — see the Variants table above.

If no source files are detected, or you need a different language than the one auto-detected, create the project manually:
```bash
serena project create --language <lang> --index
```
> **Note:** For java/c/c-pico/68k variants, if indexing fails with a timeout error on first use, run `serena project index` again — LSP servers require a warm-up period on first launch.

> **Note:** For the gowin variant, Serena detects Python helper/testbench scripts only. No Verilog LSP is available; use Gowin EDA or Yosys directly for HDL synthesis and simulation.

> **Note:** For the java-angular variant, Serena detects all present languages (java, angular, python) and creates a single polyglot project (`.serena/project.yml` lists all of them, never listing typescript alongside angular). A warning prints at init if Angular source is present without `node_modules`.

## Persistence

All mutable state lives in `.claudeproject/` at the workspace root (gitignored). Configs, credentials, and caches survive container restarts as long as the same host directory is mounted.

What is persisted:
- **Claude Code config** (`~/.claude/`) — settings, prompts, MCP registrations. Note: `settings.json` here is per-project and not part of the pulled config repo; container-wide defaults live in the image's managed settings file instead (see Configuration below).
- **Serena config** (`~/.serena/`) — Serena configuration and project data
- **Maven cache** (`~/.m2/`) — downloaded dependencies (java, java-docker, and java-angular variants)
- **npm cache** (`~/.npm/`) — downloaded packages (java-angular variant), makes `npm ci` after the first fast and network-independent
- **Docker image storage** (`~/.local/share/docker/`) — inner Docker daemon's data-root (java-docker variant only); persisted so Testcontainers/Dev Services image pulls (postgres, kafka, ryuk, etc.) survive a relaunch, unlike image-dev's ephemeral inner storage
- **Shell history** (`~/.bash_history`)
- **Claude Code credentials** (`~/.claude.json`) — API tokens and onboarding state

## Troubleshooting

**Serena tools don't appear in Claude Code**
The MCP registration runs automatically but suppresses errors. Run the command manually:
```bash
claude mcp add serena -- serena start-mcp-server --context ide-assistant --project /workspace
```

**Indexing is slow or fails on first launch**
LSP servers have a cold-start issue where their initial startup exceeds Serena's 10-second LSP timeout. The init script retries with 5-second delays between attempts. The number of retries varies by variant (3 for java, 2 for c/c-pico/68k).

**image-dev / java-docker: Docker daemon fails to start (rootless DinD)**
Rootless DinD requires kernel user namespace support (`sysctl kernel.unprivileged_userns_clone`). If `start-dockerd.sh` times out waiting for the daemon, check kernel support. Fallback: replace `SECURITY_ARGS` in `launch.sh` with `--privileged` for privileged-mode DinD (no Dockerfile changes needed).

**image-dev / java-docker: fuse-overlayfs fails (slow builds or device error)**
Requires `/dev/fuse` accessible via the `--device /dev/fuse` flag. If builds are unexpectedly slow or fail with storage driver errors, the daemon may have fallen back to `vfs`. Pass `--storage-driver vfs` explicitly in `start-dockerd.sh` to force vfs mode.

**image-dev: Inner images present after container restart**
Inner daemon storage at `/home/codeuser/.local/share/docker` is in-container only (no host volume mount). Images are discarded on container exit by design. If images persist, a volume was mounted manually — remove it to restore ephemeral behavior.

**java-docker: inner images persist across relaunch**
Unlike image-dev, java-docker bind-mounts `.claudeproject/docker` to the inner daemon's data-root so Testcontainers/Dev Services image pulls survive a relaunch. The host-side files under `.claudeproject/docker` are owned by subuids (100000+), not your host user, so removing them (e.g. to reclaim disk space or force a clean pull) requires `sudo rm -rf .claudeproject/docker`.

**java-docker: switching storage drivers breaks the persisted data-root**
If the inner daemon ever falls back between `fuse-overlayfs` and `vfs` (see the fuse-overlayfs entry above), the persisted `.claudeproject/docker` data-root is not portable between storage drivers. Wipe it with `sudo rm -rf .claudeproject/docker` before relaunching under a different driver, then let the daemon repopulate it.

**java-docker: cannot reach `mvn quarkus:dev` from the host**
Quarkus dev mode binds `localhost` inside the container by default, so the host-published port 8080 will not reach it even though `launch.sh` publishes it. Pass the host bind flag explicitly:
```bash
mvn quarkus:dev -Dquarkus.http.host=0.0.0.0
```

**java-docker: tests fail with opaque "container died" errors**
The combined memory footprint of JDT-LS (`-Xmx2G`), the rootless `dockerd` daemon, the Surefire test JVM, and any Dev Services containers (postgres, kafka, etc.) is roughly 6GB. If the host runs out of memory, Testcontainers/Dev Services report the symptom (a container that unexpectedly exited) rather than the cause. Give the host at least 8GB of memory when running java-docker.

**Credentials not saved after first session**
This happens if the container was killed with `docker kill` instead of `docker stop`. Re-launch and complete the onboarding flow again, then exit normally or use `docker stop`.

**Config clone fails on first launch (container exits)**
The container needs to reach `github.com` to clone configuration on first launch. If the clone fails, the container exits. Configure Docker's proxy settings or pre-populate `.claudeproject/.claude/` with your config files before launching.

**Config update warns on subsequent launches (non-fatal)**
On subsequent launches, the init script runs `git pull` to update config. If this fails (e.g., network unavailable), the container continues with the previously cloned config and prints a warning.

**gowin: pragma protect / encrypted IP cores fail in OSS flow**
The `fifo_hs.v` and other IP cores using `pragma protect` (encrypted IP) only work with the proprietary Gowin EDA (`gw_sh` or IDE). The OSS Yosys/Apicula flow cannot decrypt these cores. Use Gowin EDA for designs that require encrypted IP.

**gowin: USB device not detected (JTAG)**
The Tang Nano 4K uses a BL702-based USB bridge. The primary VID:PID is `28e9:0189` (Sipeed); some board revisions use `0403:6010` (FTDI VID). Verify your board:
```bash
lsusb -d 28e9:0189   # Sipeed/BL702 primary
lsusb -d 0403:6010   # FTDI-VID variant
```
The host must have udev rules granting `plugdev` group access. Install the rules file from this repo:
```bash
sudo cp resources/udev/99-tangnano.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
```
Verify the `plugdev` group GID matches between host and container (both should be GID 46 on Ubuntu):
```bash
getent group plugdev   # run on host and inside container
```
If GIDs differ (non-Ubuntu host), use `--privileged` as a workaround.
The container needs `/dev/bus/usb` and `/run/udev` bind-mounts (handled automatically by `launch.sh` for the gowin variant).

**gowin: Serial device not accessible after container start**
Serial device nodes (`/dev/ttyUSB*`, `/dev/ttyACM*`) are bound at container start via `--device` flags. If the board is connected after `launch.sh` runs, the serial node will not be present inside the container. Connect the Tang Nano 4K before running `launch.sh`. JTAG via `/dev/bus/usb` (directory bind-mount) handles hot-plug for libusb-based tools such as `openFPGALoader --detect`.

**kicad: only the file-based (SWIG) backend works headless**
The KiCAD-MCP-Server has two backends: SWIG (`import pcbnew`, edits `.kicad_pcb`/`.kicad_sch` files directly) and IPC (`kipy`, real-time control of a *running* KiCad). KiCad 9's IPC API requires a live GUI and offers no plot/export; a headless `api-server` only exists in KiCad 11. This container has no display, so it defaults to `KICAD_BACKEND=swig`. File-based design, DRC/ERC, and plotting work; live-UI synchronization does not. (To experiment with IPC you would need to add `xvfb`, run the KiCad GUI under it with the API server enabled, and set `KICAD_BACKEND=ipc`.)

**kicad: MCP tools don't appear / `No module named 'pcbnew'`**
The MCP's Python backend imports `pcbnew` from the system `kicad` package (`/usr/lib/python3/dist-packages`). The MCP venv at `/opt/kicad-mcp/.venv` is created with `--system-site-packages` so it inherits those bindings, and registration points the Node layer at that interpreter via `KICAD_PYTHON`. The image build asserts `import pcbnew` succeeds, so a runtime failure usually means the registration env was lost — re-register manually:
```bash
claude mcp add kicad \
  -e KICAD_PYTHON=/opt/kicad-mcp/.venv/bin/python \
  -e KICAD_BACKEND=swig \
  -- node /opt/kicad-mcp/dist/index.js
```

**gowin: ftdi_sio driver conflict (FTDI VID boards only)**
If your board uses FTDI VID `0x0403`, the host kernel may autobind the `ftdi_sio` driver, which blocks libusb access from inside the container. Unload the driver on the host before running `openFPGALoader`:
```bash
sudo rmmod ftdi_sio
```
To rebind after flashing: `sudo modprobe ftdi_sio`.
This does not affect boards with Sipeed VID `0x28e9`; the BL702 chip with Sipeed VID does not trigger `ftdi_sio` autobind. On modern kernels (5.x+), `USBDEVFS_DISCONNECT` requires only device node write access, not `CAP_SYS_RAWIO`; adding that capability weakens isolation for Sipeed VID boards that do not trigger `ftdi_sio`.

**gowin: Recommended flashing tool**
Use `openFPGALoader` for flashing from inside the container. It is libusb-based, requires no GUI, and supports Tang Nano 4K directly:
```bash
openFPGALoader --cable tangnano4k --detect
openFPGALoader --cable tangnano4k --board tangnano4k bitstream.fs
```
The bundled Gowin Programmer (`/opt/gowin-eda/Programmer/bin`) is available but its USB enumeration in headless mode is untested.

**gowin: Standard edition requires Sipeed license server**
The Education edition (default) needs no license. If you override to the Standard edition with `--build-arg GOWIN_EDA_URL=...`, Gowin EDA will prompt for a license server at startup. Use Sipeed's free online server: `gowinlic.sipeed.com:10559`.

**gowin: CDN download fails at build time**
If `curl` fails with a non-200 error or the file-size guard triggers, the Gowin EDA CDN URL may have changed. Update `GOWIN_EDA_URL` in `Dockerfile.gowin` or override via `--build-arg GOWIN_EDA_URL=<new-url>`. The current default is the Education edition V1.9.11.03.

**gowin: Referer header required for CDN downloads**
The Gowin CDN at `cdn.gowinsemi.com.cn` requires the `Referer: https://www.gowinsemi.com/` header. A bare `curl` without `--referer` returns error HTML with HTTP 200 — no download error, silent extraction failure with no diagnostic trail. The Dockerfile includes this header; if you replicate the download outside Docker, include `--referer https://www.gowinsemi.com/`.

**gowin: Education vs Standard edition device support**
The Education edition (default) supports Tang Nano 1K/4K/9K/20K and Primer 20K/25K without a license server.
The Standard edition supports additional devices and IP cores but requires Sipeed's license server at `gowinlic.sipeed.com:10559`.
Override: `--build-arg GOWIN_EDA_URL=https://cdn.gowinsemi.com.cn/Gowin_V1.9.11.03_Standard_Linux.tar.gz`

**gowin: Programmer bundled in EDA tarball**
The Gowin Programmer binary is bundled inside the EDA tarball and accessible at `/opt/gowin-eda/Programmer/bin`. For Linux flashing, `openFPGALoader` is recommended. The bundled Programmer is available for edge cases requiring proprietary programming features.

**gowin: nextpnr-gowin is a transitional package**
`nextpnr-gowin` is a transitional package that maps to `nextpnr-himbaechel` in newer Ubuntu versions. If `apt-get install nextpnr-gowin` fails on a future Ubuntu release, replace it with `nextpnr-himbaechel` in `Dockerfile.gowin`.

**gowin: GW1NSR primitives may fail in OSS flow**
The GW1NSR-4C (Tang Nano 4K) has less complete Yosys/Apicula support than simpler GW1N parts. Primitives including PLLVR, OSER10, and TLVDS_OBUF may fail in the OSS flow. Verify designs using these primitives against Gowin EDA (`gw_sh`) if OSS synthesis or PnR reports unknown primitives.

## Architecture

For contributors and maintainers — details on how the container works internally.

### Key Directories

- `/workspace` — mounted host project directory
- `/workspace/.claudeproject/` — persisted configs, auth tokens, Maven cache (gitignored)
- `/home/codeuser/serena/` — Serena installation (`$SERENA_HOME`)
- `/opt/cli-tools/.venv/` — isolated Python venv for CLI tools (httpie, yq, csvkit, litecli, pgcli); separate from Serena's venv to avoid dependency conflicts
- `/opt/jdtls/` — Eclipse JDT Language Server installation (java variant only)
- `/opt/java/openjdk/` — JDK installation (`$JAVA_HOME`; java, x86, snes variants)
- `/opt/node/` — variant-local Node 24 LTS, root-owned, PATH-shadows the base image's apt Node (java-angular variant only)
- `/opt/ghidra/` — Ghidra installation (x86, snes variants)
- `/opt/gowin-eda/` — Gowin EDA installation (gowin variant)
- `/opt/pico-sdk/` — Raspberry Pi Pico SDK (c-pico variant)
- `/usr/local/share/claude-env/` — immutable config templates baked into image

### Container Lifecycle

1. **Build time** (`Dockerfile.base` + `Dockerfile.<variant>`): Base image installs shared infrastructure; variant image adds domain toolchain and copies variant-specific Serena config. `VARIANT` env var is baked in.
   - **image-dev / java-docker exception**: `start-dockerd.sh` replaces `init-workspace.sh` as the ENTRYPOINT, shared by both variants. It starts `dockerd-rootless.sh` as codeuser, polls until the daemon is ready, then execs `init-workspace.sh` to complete the standard init flow.
2. **Runtime entry** (`resources/scripts/init-workspace.sh`): The ENTRYPOINT script provisions bind-mounted directories, clones/updates Claude config, copies Serena config templates, auto-detects project language, indexes via Serena, and registers the MCP server.
3. **Interactive session**: Drops into bash; user runs `claude` to start AI-assisted coding.

**java-docker startup and Testcontainers path** — the DinD exception above, extended with the Quarkus/Testcontainers path a `mvn test` takes once the container is running:

```
docker run (java-docker)
      |
      v
ENTRYPOINT start-dockerd.sh
      |-- dockerd-rootless.sh --storage-driver fuse-overlayfs   (background)
      |-- export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock (runtime UID, not baked-in 1000)
      |-- poll `docker info` for up to 30s
      |     `-- daemon never ready --> script exits non-zero --> launch fails loudly
      v
exec init-workspace.sh            (standard init: mounts, Claude/Serena config, MCP registration)
      v
interactive bash  -->  mvn quarkus:dev / mvn test
                              |
                              v
                    Testcontainers / Quarkus Dev Services
                              |
                              v
                    reads DOCKER_HOST --> talks to the rootless daemon started above
                              |
                              v
                    pulls postgres/kafka/ryuk into /home/codeuser/.local/share/docker
                              |
                              v
                    bind-mounted to host .claudeproject/docker --> image pulls survive relaunch
```

Host reachability is asymmetric: Testcontainers/Dev Services talk to the daemon over `DOCKER_HOST` and reach inner container ports over the dev container's own loopback, so no port publishing is needed for them. `mvn quarkus:dev` and an attached debugger are the only consumers of the host-published `8080`/`5005` ports (see Troubleshooting above).

### Persistence Implementation

`launch.sh` pre-creates `.claudeproject/.claude`, `.claudeproject/.serena` on the host and bind-mounts them to their `~/` counterparts, so changes inside the container persist directly to the host. `.m2` is mounted for the java and java-docker variants. java-docker additionally bind-mounts `.claudeproject/docker` to the inner Docker daemon's data-root (`~/.local/share/docker`), so pulled images persist across relaunches instead of being discarded like image-dev's ephemeral inner storage.

`.claude.json` uses two-mode persistence:
- **Consecutive launch:** `launch.sh` detects `"hasCompletedOnboarding": true` in `.claudeproject/.claude.json` and bind-mounts it to `~/.claude.json`.
- **First launch:** No `.claude.json` exists yet. An EXIT trap copies `~/.claude.json` to `.claudeproject/.claude.json` when the session ends.

### Configuration

- **Serena config templates**: `resources/config/serena_config.java.yml` (JDTLS), `serena_config.auto.yml` (clangd auto-managed), `serena_config.disabled.yml` (binary analysis variants)
- **JDTLS launcher**: `resources/scripts/jdtls.sh` — accepts `--workspace=` arg, 2G max heap
- **Claude config**: Pulled from `github.com/largomodo/claude-config` (fork of `solatis/claude-config`)
- **Claude managed settings**: `resources/config/managed-settings.json` is copied to `/etc/claude-code/managed-settings.json` in the base image. Claude Code reads this path on every startup and it outranks user/project/local settings, so these defaults apply to every variant and every mounted project regardless of the persisted `~/.claude/settings.json`. Currently: Artifact tool disabled (`enableArtifact: false` plus a `permissions.deny` rule for `Artifact`) and the claude.ai session link omitted from commits (`attribution.sessionUrl: false`). Verify inside a session with `/status` (the `Setting sources` line names the managed file).

### CLI Tool Tiers

Tools are split into three tiers based on image size constraints (target: <5GB) and usage frequency.

**Tier 1 — System utilities (baked in via apt in Dockerfile.base):**
poppler-utils (needed for programmatic text extraction via pdftotext/grep; Claude Code's native PDF reading is visual-only), pandoc, sqlite3, graphviz, tesseract-ocr, shellcheck, ripgrep, fd-find, tree, unzip/zip/xz-utils, file, less, man-db, postgresql-client, imagemagick, ffmpeg, net-tools, dnsutils, iputils-ping, traceroute, strace, htop, ncdu. Note: `build-essential` in the base apt layer already provides gcc, g++, make — do not add them here.

**Tier 2 — Python CLI tools (baked in via uv, `/opt/cli-tools/.venv`):**
httpie (`http`), yq, csvkit, litecli, pgcli.

These are installed in a dedicated venv separate from Serena's `~/serena/.venv` to prevent dependency conflicts. The venv bin directory is prepended to `PATH` so tools are available without activation.

> **Note:** For Java projects, the Gradle wrapper (`gradlew`) is the recommended build approach. A specific Gradle version is not baked into the image to avoid version mismatch with the wrapper's declared version.

## External References

*   **[largomodo/claude-config](https://github.com/largomodo/claude-config)** — Claude Code settings and prompts (forked from [solatis/claude-config](https://github.com/solatis/claude-config))
*   **[oraios/serena](https://github.com/oraios/serena)** — Serena autonomous coding agent
