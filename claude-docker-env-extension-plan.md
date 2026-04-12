# Plan

## Overview

The containerized dev environment lacks common CLI tools for document processing, database interaction, image manipulation, search, diagram rendering, OCR, network debugging, and linting that Claude Code agents frequently need during development sessions.

**Approach**: Three-tier installation strategy: Tier 1+2 apt and Python packages baked into the image in separate Docker layers for cache efficiency; Tier 3 heavyweight tools (language runtimes, mermaid-cli) available via an idempotent on-demand install script using sudo.

## Planning Context

### Decision Log

| ID | Decision | Reasoning Chain |
|---|---|---|
| DL-001 | Tiered Docker layers for CLI tool installation | Existing apt block is stable and tested -> adding packages there invalidates cache on any tool change -> separate layer preserves base layer cache at the cost of an additional apt-get update (~30-50MB for package index re-download, cleaned up in same layer). This layer overhead is acceptable because it prevents cache invalidation of the larger base layer on tool-only changes. |
| DL-002 | Python CLI tools installed in isolated uv venv at /opt/cli-tools | Serena uses its own venv at ~/serena/.venv -> pip installing into same venv risks dependency conflicts -> separate /opt/cli-tools venv with PATH prepend keeps tools available without collision |
| DL-003 | Tier 3 on-demand tools use pre-staged install script with sudo | Container runs as codeuser (non-root) -> apt-get requires root -> install sudo with passwordless access for codeuser enables on-demand installs without rebuilding image. Security tradeoff: passwordless sudo is acceptable because (1) container is single-user local dev, not shared/production, (2) sudo scope is container-only with no host escalation path, (3) alternative (pre-staged binaries) would require predicting all on-demand needs at build time. RISK-003 documents this exposure. |
| DL-004 | mermaid-cli in Tier 3 on-demand due to Chromium dependency | mermaid-cli pulls Chromium (~400MB) -> baking into image would push past 5GB target -> on-demand install keeps base image lean for users who dont need diagram rendering |
| DL-005 | Gradle not baked in; gradlew wrapper pattern sufficient | Most Java projects use gradle wrapper (gradlew) which downloads its own gradle -> baking in a specific gradle version risks version mismatch -> wrapper pattern is the Gradle teams recommended approach |

### Rejected Alternatives

| Alternative | Why Rejected |
|---|---|
| Kitchen-sink image with all language runtimes baked in | Would push image size past 10GB, far exceeding the 5GB target; most sessions only need 1-2 runtimes (ref: DL-004) |
| Install-on-demand for everything including Tier 1+2 tools | Runtime apt-get is slow and may lack root access; frequently-used tools should be pre-baked for instant availability (ref: DL-001) |

### Constraints

- MUST: not break existing JDK 21/JDTLS/Node 18/Maven/Serena/Claude Code setup
- MUST: tools must work as non-root user (codeuser)
- MUST: Ubuntu 24.04 package compatibility
- SHOULD: keep image size reasonable (currently ~2-3GB, target <5GB with all Tier 1+2)
- SHOULD: optimize Docker layer caching — stable tool layers before volatile ones
- SHOULD: use --no-install-recommends to minimize apt bloat
- MUST-NOT: install Tier 3 language runtimes directly in image (use on-demand script instead)

### Known Risks

- **pip/venv conflicts with Serena's Python environment**: DL-002 isolates CLI tools in /opt/cli-tools/.venv, completely separate from Serena's ~/serena/.venv
- **Image size exceeding 5GB target after adding all Tier 1+2 packages**: Use --no-install-recommends, clean apt lists after install, keep mermaid-cli and runtimes in Tier 3 on-demand
- **Passwordless sudo for codeuser creates security exposure in shared/CI environments**: Container is single-user local dev; sudo scoped to container only, not host. Acceptable tradeoff for dev convenience per DL-003
- **Ubuntu 24.04 package availability — some tools may not be in default repos**: All Tier 1+2 packages verified available in Ubuntu 24.04 universe repo; Tier 3 dotnet uses Microsoft PPA

## Invisible Knowledge

### System

Containerized dev environment running Ubuntu 24.04 with JDK 21, JDTLS, Node 18, Maven, Python 3.12, Claude Code CLI, and Serena MCP agent. Container runs as non-root codeuser with /workspace as working directory.

### Invariants

- The container mounts host projects at /workspace via bind mount in launch.sh — tools must not assume /workspace contents are static or image-resident
- build-essential already provides gcc, g++, make — these must not be redundantly installed

### Tradeoffs

- Claude Code Read tool can natively read PDFs visually, but poppler-utils is still needed for programmatic text extraction (grep, pdftotext pipelines) — both capabilities serve different use cases
- mermaid-cli pulls Chromium (~400MB) so it belongs in Tier 3 on-demand — baking it in would add ~400MB to every image pull even for users who never render diagrams

## Milestones

### Milestone 1: Tier 1+2 apt packages

**Files**: Dockerfile

**Acceptance Criteria**:

- docker build completes without errors
- All Tier 1+2 apt packages are present: poppler-utils, pandoc, sqlite3, graphviz, tesseract-ocr, shellcheck, ripgrep, fd-find, tree, unzip, zip, xz-utils, file, less, man-db, postgresql-client, imagemagick, ffmpeg, net-tools, dnsutils, iputils-ping, traceroute, strace, htop, ncdu
- sudo is installed and codeuser can run 'sudo -n true' without password prompt
- Existing tools (java, javac, node, npm, mvn, git, curl, wget, jq) still function correctly

#### Code Intent

- **CI-M-001-001** `Dockerfile`: Insert a new RUN apt-get block after line 47 (after the existing apt-get install block and its cache cleanup) but before the Python symlink on line 50. This block installs Tier 1 packages (poppler-utils, pandoc, sqlite3, graphviz, tesseract-ocr, shellcheck, ripgrep, fd-find, tree, unzip, zip, xz-utils, file, less, man-db) and Tier 2 packages (postgresql-client, imagemagick, ffmpeg, net-tools, dnsutils, iputils-ping, traceroute, strace, htop, ncdu). Ends with rm -rf /var/lib/apt/lists/* for cache cleanup. Also install sudo in this block and grant codeuser passwordless sudo via echo "codeuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/codeuser. (refs: DL-001, DL-003)

#### Code Changes

**CC-M-001-001** (Dockerfile) - implements CI-M-001-001

**Code:**

```diff
--- a/Dockerfile
+++ b/Dockerfile
@@ -47,6 +47,26 @@
     && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
 
 # Create Python symlink for compatibility
+RUN apt-get update && \
+    apt-get install -y --no-install-recommends \
+    poppler-utils \
+    pandoc \
+    sqlite3 \
+    graphviz \
+    tesseract-ocr \
+    shellcheck \
+    ripgrep \
+    fd-find \
+    tree \
+    unzip \
+    zip \
+    xz-utils \
+    file \
+    less \
+    man-db \
+    postgresql-client \
+    imagemagick \
+    ffmpeg \
+    net-tools \
+    dnsutils \
+    iputils-ping \
+    traceroute \
+    strace \
+    htop \
+    ncdu \
+    sudo \
+    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
+
+RUN echo "codeuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/codeuser && \
+    chmod 0440 /etc/sudoers.d/codeuser
+
 RUN ln -sf /usr/bin/python3 /usr/bin/python
```

**Documentation:**

```diff
--- a/Dockerfile
+++ b/Dockerfile
@@ -47,6 +47,10 @@ RUN apt-get update && \
     && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
 
 # Create Python symlink for compatibility
+# Separate layer from the base apt block so tool-only changes don't invalidate
+# the larger base layer cache. apt lists are cleaned in the same RUN to avoid
+# persisting the package index in the layer. (ref: DL-001)
 RUN apt-get update && \
     apt-get install -y --no-install-recommends \
     poppler-utils \
@@ -70,6 +74,8 @@ RUN apt-get update && \
     sudo \
     && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
 
+# Grants codeuser passwordless sudo for on-demand tool installs. Acceptable
+# in single-user local dev containers; not for shared or CI environments. (ref: DL-003)
 RUN echo "codeuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/codeuser && \
     chmod 0440 /etc/sudoers.d/codeuser

```


### Milestone 2: Python CLI tools venv

**Files**: Dockerfile

**Acceptance Criteria**:

- /opt/cli-tools/.venv/bin/python exists and is executable
- httpie, yq, csvkit, litecli, pgcli commands are on PATH for codeuser
- Serena's venv at ~/serena/.venv is unmodified — serena-agent command still works
- codeuser can run 'http --version', 'yq --version', 'csvstat --version' successfully

#### Code Intent

- **CI-M-002-001** `Dockerfile`: After the existing uv install for root (line 104) and before USER codeuser switch (line 108), add a RUN block that: creates /opt/cli-tools directory, runs uv venv /opt/cli-tools/.venv, then uv pip install --python /opt/cli-tools/.venv/bin/python into that venv the following packages: httpie, yq, csvkit, litecli, pgcli. After the USER codeuser line, add ENV PATH=/opt/cli-tools/.venv/bin:$PATH to make these tools available. Ensure /opt/cli-tools is owned by root but world-readable/executable so codeuser can run the tools. (refs: DL-002)

#### Code Changes

**CC-M-002-001** (Dockerfile) - implements CI-M-002-001

**Code:**

```diff
--- a/Dockerfile
+++ b/Dockerfile
@@ -103,6 +103,17 @@
 # Install uv for Python package management (as root for global availability)
 RUN curl -LsSf https://astral.sh/uv/install.sh | sh
 ENV PATH="/root/.cargo/bin:${PATH}"
 
+RUN mkdir -p /opt/cli-tools && \
+    uv venv /opt/cli-tools/.venv && \
+    uv pip install \
+        --python /opt/cli-tools/.venv/bin/python \
+        httpie \
+        yq \
+        csvkit \
+        litecli \
+        pgcli && \
+    chmod -R a+rX /opt/cli-tools
+
 # Switch to codeuser for the rest of the setup
 USER codeuser
 WORKDIR /home/codeuser
 
 # Set up environment paths for codeuser
-ENV PATH="/home/codeuser/.local/bin:/home/codeuser/.cargo/bin:${PATH}"
+ENV PATH="/opt/cli-tools/.venv/bin:/home/codeuser/.local/bin:/home/codeuser/.cargo/bin:${PATH}"
```

**Documentation:**

```diff
--- a/Dockerfile
+++ b/Dockerfile
@@ -103,6 +103,11 @@ RUN curl -LsSf https://astral.sh/uv/install.sh | sh
 ENV PATH="/root/.cargo/bin:${PATH}"
 
+# Isolated venv at /opt/cli-tools keeps httpie/yq/csvkit/litecli/pgcli
+# dependencies separate from Serena's venv at ~/serena/.venv.
+# chmod a+rX allows codeuser to execute tools without being the venv owner. (ref: DL-002)
 RUN mkdir -p /opt/cli-tools && \
     uv venv /opt/cli-tools/.venv && \
     uv pip install \
@@ -115,6 +120,7 @@ RUN mkdir -p /opt/cli-tools && \
     && chmod -R a+rX /opt/cli-tools
 
 # Switch to codeuser for the rest of the setup
 USER codeuser
 WORKDIR /home/codeuser
 
 # Set up environment paths for codeuser
+# /opt/cli-tools/.venv/bin listed first so CLI tool binaries shadow any conflicting names. (ref: DL-002)
 ENV PATH="/opt/cli-tools/.venv/bin:/home/codeuser/.local/bin:/home/codeuser/.cargo/bin:${PATH}"

```


### Milestone 3: Tier 3 on-demand install script

**Files**: Dockerfile, resources/scripts/install-on-demand.sh, CLAUDE.md

**Acceptance Criteria**:

- install-on-demand script is at /usr/local/bin/install-on-demand and is executable
- Running 'install-on-demand' with no args prints usage listing supported tools (mermaid, golang, rust, dotnet)
- Running 'install-on-demand unknown-tool' prints error and exits non-zero
- Each tool section is idempotent — running twice does not error or reinstall

#### Code Intent

- **CI-M-003-001** `resources/scripts/install-on-demand.sh`: Create a new shell script that accepts a tool name argument and installs Tier 3 tools on demand. Supported tools: mermaid (installs @mermaid-js/mermaid-cli globally via npm plus chromium-browser via apt), golang (installs golang-go via apt), rust (installs via rustup.rs), dotnet (installs dotnet-sdk-8.0 via Microsoft apt repo). Script validates the argument, prints usage for unknown tools, and uses sudo for apt operations. Each tool section is idempotent (checks if already installed before acting). (refs: DL-003, DL-004, DL-005)
- **CI-M-003-002** `Dockerfile`: COPY the install-on-demand.sh script to /usr/local/bin/install-on-demand and chmod +x it. This COPY goes in the root section near the other COPY commands (near line 87-88 area, alongside the jdtls.sh copy). (refs: DL-003)

#### Code Changes

**CC-M-003-001** (resources/scripts/install-on-demand.sh) - implements CI-M-003-001

**Code:**

```diff
--- /dev/null
+++ b/resources/scripts/install-on-demand.sh
@@ -0,0 +1,89 @@
+#!/bin/bash
+set -euo pipefail
+
+TOOL="${1:-}"
+
+usage() {
+    cat <<EOF
+Usage: install-on-demand <tool>
+
+Install Tier 3 tools on demand. Supported tools:
+
+  mermaid   @mermaid-js/mermaid-cli + chromium-browser
+  golang    Go language runtime (golang-go)
+  rust      Rust toolchain via rustup
+  dotnet    .NET SDK 8.0 via Microsoft apt repo
+
+Each install is idempotent: running twice is safe.
+EOF
+}
+
+if [ -z "$TOOL" ]; then
+    usage
+    exit 0
+fi
+
+case "$TOOL" in
+    mermaid)
+        if command -v mmdc >/dev/null 2>&1; then
+            echo "mermaid-cli is already installed."
+        else
+            echo "Installing chromium-browser..."
+            sudo apt-get update -qq
+            sudo apt-get install -y --no-install-recommends chromium-browser
+            sudo rm -rf /var/lib/apt/lists/*
+            echo "Installing @mermaid-js/mermaid-cli..."
+            sudo npm install -g @mermaid-js/mermaid-cli
+            echo "mermaid-cli installed: $(mmdc --version)"
+        fi
+        ;;
+    golang)
+        if command -v go >/dev/null 2>&1; then
+            echo "Go is already installed: $(go version)"
+        else
+            echo "Installing golang-go..."
+            sudo apt-get update -qq
+            sudo apt-get install -y --no-install-recommends golang-go
+            sudo rm -rf /var/lib/apt/lists/*
+            echo "Go installed: $(go version)"
+        fi
+        ;;
+    rust)
+        if command -v rustc >/dev/null 2>&1; then
+            echo "Rust is already installed: $(rustc --version)"
+        else
+            echo "Installing Rust via rustup..."
+            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
+            echo "Rust installed. Add to PATH: source \$HOME/.cargo/env"
+            echo "Or start a new shell session."
+        fi
+        ;;
+    dotnet)
+        if command -v dotnet >/dev/null 2>&1; then
+            echo ".NET is already installed: $(dotnet --version)"
+        else
+            echo "Adding Microsoft apt repository..."
+            sudo apt-get update -qq
+            sudo apt-get install -y --no-install-recommends wget ca-certificates
+            wget -q https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
+            sudo dpkg -i /tmp/packages-microsoft-prod.deb
+            rm /tmp/packages-microsoft-prod.deb
+            sudo apt-get update -qq
+            sudo apt-get install -y --no-install-recommends dotnet-sdk-8.0
+            sudo rm -rf /var/lib/apt/lists/*
+            echo ".NET installed: $(dotnet --version)"
+        fi
+        ;;
+    *)
+        echo "Error: unknown tool $TOOL"
+        echo ""
+        usage
+        exit 1
+        ;;
+esac
```

**Documentation:**

```diff
--- /dev/null
+++ b/resources/scripts/install-on-demand.sh
@@ -1,3 +1,9 @@
 #!/bin/bash
+# install-on-demand - Install Tier 3 tools at runtime inside the container.
+#
+# Tier 3 tools are excluded from the baked image to keep image size under 5GB.
+# mermaid-cli is the primary driver: its Chromium dependency adds ~400MB alone.
+# Language runtimes (Go, Rust, .NET) are rarely needed in the same session.
+# Requires passwordless sudo for codeuser (ref: DL-003, DL-004).
 set -euo pipefail
 
 TOOL="${1:-}"
@@ -20,6 +26,7 @@ if [ -z "$TOOL" ]; then
 fi
 
 case "$TOOL" in
+    # ~400MB chromium install; kept out of baked image (ref: DL-004)
     mermaid)
         if command -v mmdc >/dev/null 2>&1; then
             echo "mermaid-cli is already installed."
@@ -35,6 +42,7 @@ case "$TOOL" in
             echo "mermaid-cli installed: $(mmdc --version)"
         fi
         ;;
+    # golang-go from Ubuntu repos; gradlew wrapper preferred for project builds (ref: DL-005)
     golang)
         if command -v go >/dev/null 2>&1; then
             echo "Go is already installed: $(go version)"
@@ -48,6 +56,7 @@ case "$TOOL" in
             echo "Go installed: $(go version)"
         fi
         ;;
+    # rustup installs to ~/.cargo; PATH update requires new shell or `source $HOME/.cargo/env`
     rust)
         if command -v rustc >/dev/null 2>&1; then
             echo "Rust is already installed: $(rustc --version)"
@@ -62,6 +71,7 @@ case "$TOOL" in
             echo "Or start a new shell session."
         fi
         ;;
+    # Microsoft PPA required; not in Ubuntu 24.04 default repos (ref: RISK-004)
     dotnet)
         if command -v dotnet >/dev/null 2>&1; then
             echo ".NET is already installed: $(dotnet --version)"

```


**CC-M-003-002** (Dockerfile) - implements CI-M-003-002

**Code:**

```diff
--- a/Dockerfile
+++ b/Dockerfile
@@ -87,6 +87,9 @@
 # Create JDT LS launcher script
 COPY resources/scripts/jdtls.sh /usr/local/bin/jdtls
 RUN chmod +x /usr/local/bin/jdtls
 
+# Install on-demand tool installer
+COPY resources/scripts/install-on-demand.sh /usr/local/bin/install-on-demand
+RUN chmod +x /usr/local/bin/install-on-demand
+
 # Create non-root user with matching UID/GID
```

**Documentation:**

```diff
--- a/Dockerfile
+++ b/Dockerfile
@@ -87,6 +87,7 @@ RUN chmod +x /usr/local/bin/jdtls
 
+# Copies install-on-demand.sh to PATH so codeuser can install Tier 3 tools at runtime. (ref: DL-003)
 COPY resources/scripts/install-on-demand.sh /usr/local/bin/install-on-demand
 RUN chmod +x /usr/local/bin/install-on-demand

```


**CC-M-003-003** (README.md)

**Documentation:**

```diff
--- a/README.md
+++ b/README.md
@@ -119,6 +119,8 @@ For contributors and maintainers — details on how the container works internally
 - `/workspace` — mounted host project directory (container working directory)
 - `/workspace/.claudeproject/` — persisted configs, auth tokens, Maven cache (gitignored)
 - `/home/codeuser/serena/` — Serena installation (`$SERENA_HOME`)
+- `/opt/cli-tools/.venv/` — isolated Python venv for CLI tools (httpie, yq, csvkit, litecli, pgcli); separate from Serena's venv to avoid dependency conflicts
 - `/opt/jdtls/` — Eclipse JDT Language Server installation
 - `/opt/java/openjdk/` — JDK installation (`$JAVA_HOME`)
 - `/usr/local/share/claude-env/` — immutable config templates baked into image
@@ -125,7 +127,7 @@ For contributors and maintainers — details on how the container works internally
 ### Container Lifecycle
 
 1. **Build time** (`Dockerfile`): Installs JDK, JDTLS, Node.js, Maven, Claude Code CLI, and Serena. Copies golden-master configs to `/usr/local/share/claude-env/`.
-2. **Runtime entry** (`resources/scripts/init-workspace.sh`): The ENTRYPOINT script provisions bind-mounted directories, clones/updates Claude config, copies Serena config templates, auto-detects project language, indexes via Serena, and registers the MCP server.
+2. **Runtime entry** (`resources/scripts/init-workspace.sh`): The ENTRYPOINT script provisions bind-mounted directories, clones/updates Claude config, copies Serena config templates, auto-detects project language, indexes via Serena, and registers the MCP server. Tier 3 tools are available via `install-on-demand <tool>` at any point during a session.
 3. **Interactive session**: Drops into bash; user runs `claude` to start AI-assisted coding.
@@ -139,6 +141,31 @@ For contributors and maintainers — details on how the container works internally
 - **Serena config template**: `resources/config/serena_config.yml` — LSP backend, web dashboard on `0.0.0.0:24282` (default Serena port; listen address configured in the yml), 240s tool timeout, JDTLS workspace at `/workspace/.jdtls-workspace`
 - **JDTLS launcher**: `resources/scripts/jdtls.sh` — accepts `--workspace=` arg, 2G max heap
 - **Claude config**: Pulled from `github.com/largomodo/claude-config` (fork of `solatis/claude-config`)
+
+### CLI Tool Tiers
+
+Tools are split into three tiers based on image size constraints (target: <5GB) and usage frequency.
+
+**Tier 1 — System utilities (baked in via apt):**
+poppler-utils, pandoc, sqlite3, graphviz, tesseract-ocr, shellcheck, ripgrep, fd-find, tree, unzip/zip/xz-utils, file, less, man-db, postgresql-client, imagemagick, ffmpeg, net-tools, dnsutils, iputils-ping, traceroute, strace, htop, ncdu.
+
+**Tier 2 — Python CLI tools (baked in via uv, `/opt/cli-tools/.venv`):**
+httpie (`http`), yq, csvkit, litecli, pgcli.
+
+These are installed in a dedicated venv separate from Serena's `~/serena/.venv` to prevent dependency conflicts. The venv bin directory is prepended to `PATH` so tools are available without activation.
+
+**Tier 3 — On-demand tools (installed at runtime via `install-on-demand`):**
+
+| Tool | Command | Notes |
+|------|---------|-------|
+| mermaid-cli | `install-on-demand mermaid` | Pulls ~400MB Chromium; kept out of baked image |
+| Go runtime | `install-on-demand golang` | Installs `golang-go` from Ubuntu repos |
+| Rust toolchain | `install-on-demand rust` | Installs via rustup to `~/.cargo`; requires new shell or `source $HOME/.cargo/env` |
+| .NET SDK 8.0 | `install-on-demand dotnet` | Requires Microsoft apt PPA; not in Ubuntu 24.04 default repos |
+
+All installs are idempotent. `install-on-demand` uses passwordless `sudo` granted to `codeuser` — acceptable for single-user local dev containers, not for shared or CI environments.
+
+> **Note:** For Java projects, the Gradle wrapper (`gradlew`) is the recommended build approach. A specific Gradle version is not baked into the image to avoid version mismatch with the wrapper's declared version.

```


**CC-M-003-004** (CLAUDE.md) - implements CI-M-003-002

**Documentation:**

```diff
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -14,6 +14,7 @@
 | `README.md`      | Architecture, design decisions, persistence model, authentication               | Understanding architecture, design decisions, component relationships         |
 | `resources/`     | Config templates and shell scripts baked into the image                          | Modifying Serena config, JDTLS launcher, or container init sequence           |
+| `resources/scripts/install-on-demand.sh` | On-demand installer for Tier 3 tools (mermaid-cli, Go, Rust, .NET); uses passwordless sudo granted to codeuser (ref: DL-003, DL-004) | Adding or modifying Tier 3 on-demand tool installs |
 
 ## Build & Run

```


**CC-M-003-005** (CLAUDE.md)

**Documentation:**

```diff
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -14,6 +14,7 @@
 | `README.md`      | Architecture, design decisions, persistence model, authentication               | Understanding architecture, design decisions, component relationships         |
 | `resources/`     | Config templates and shell scripts baked into the image                          | Modifying Serena config, JDTLS launcher, or container init sequence           |
+| `resources/scripts/install-on-demand.sh` | On-demand installer for Tier 3 tools (mermaid-cli, Go, Rust, .NET); uses passwordless sudo granted to codeuser (ref: DL-003, DL-004) | Adding or modifying Tier 3 on-demand tool installs |
 
 ## Build & Run

```

