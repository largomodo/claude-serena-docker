FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Java 21 LTS configuration
ARG JAVA_LANG_VERSION=21
ARG ADOPTIUM_VERSION=21.0.10
ARG ADOPTIUM_BUILD=7
ARG JDK_URL="https://github.com/adoptium/temurin${JAVA_LANG_VERSION}-binaries/releases/download/jdk-${ADOPTIUM_VERSION}%2B${ADOPTIUM_BUILD}/OpenJDK${JAVA_LANG_VERSION}U-jdk_x64_linux_hotspot_${ADOPTIUM_VERSION}_${ADOPTIUM_BUILD}.tar.gz"
ARG JDK_CHECKSUM_URL="https://github.com/adoptium/temurin${JAVA_LANG_VERSION}-binaries/releases/download/jdk-${ADOPTIUM_VERSION}%2B${ADOPTIUM_BUILD}/OpenJDK${JAVA_LANG_VERSION}U-jdk_x64_linux_hotspot_${ADOPTIUM_VERSION}_${ADOPTIUM_BUILD}.tar.gz.sha256.txt"

# Ghidra headless configuration
# ViewtifulSlayer SNES loader/processor forks require Ghidra 12.x API;
# incompatible with 11.x. (DL-001, RISK-001, RISK-002)
ARG GHIDRA_VERSION=12.0.4
ARG GHIDRA_DATE=20260303
ARG GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_DATE}.zip"

# User configuration
ARG USER_UID=1000
ARG USER_GID=1000

# Update package lists and install essential packages
RUN apt-get update && \
    apt-get install -y \
    # Python and pip
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    # Node.js and npm
    nodejs \
    npm \
    # Disassembly tools
    nasm \
    radare2 \
    upx-ucl \
    unzip \
    # Version control and utilities
    git \
    curl \
    wget \
    # Build essentials
    build-essential \
    # Additional utilities
    ca-certificates \
    gnupg \
    lsb-release \
    vim \
    jq \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Create Python symlink for compatibility
RUN ln -sf /usr/bin/python3 /usr/bin/python

# Download and install Temurin OpenJDK 21 LTS
RUN set -eux; \
    # Download the checksum file first
    curl -L -o openjdk.tar.gz.sha256.txt "${JDK_CHECKSUM_URL}"; \
    # Update the filename in the checksum file to match our downloaded filename
    sed -i 's/OpenJDK.*\.tar\.gz/openjdk.tar.gz/' openjdk.tar.gz.sha256.txt; \
    # Download the JDK tarball
    curl -L -o openjdk.tar.gz "${JDK_URL}"; \
    # Verify the checksum for security and integrity
    sha256sum -c openjdk.tar.gz.sha256.txt; \
    # Create the installation directory
    mkdir -p /opt/java/openjdk; \
    # Extract the archive, stripping the top-level directory
    tar -zxvf openjdk.tar.gz -C /opt/java/openjdk --strip-components=1; \
    # Clean up the downloaded files
    rm openjdk.tar.gz openjdk.tar.gz.sha256.txt

# Set JAVA_HOME
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# This pre-loads core JVM classes into a shared archive
RUN java -Xshare:dump 2>/dev/null || true

# Download and install Ghidra headless
# SHA-256 declared as ARG so it can be overridden when pinning to a fallback
# version (e.g., 12.0.3) without editing the RUN block. (RISK-001, RISK-002)
ARG GHIDRA_SHA256="c3b458661d69e26e203d739c0c82d143cc8a4a29d9e571f099c2cf4bda62a120"
RUN set -eux; \
    mkdir -p /opt/ghidra; \
    wget -q -O ghidra.zip "${GHIDRA_URL}"; \
    echo "${GHIDRA_SHA256}  ghidra.zip" | sha256sum -c -; \
    unzip -q ghidra.zip -d /opt/ghidra_tmp; \
    mv /opt/ghidra_tmp/ghidra_${GHIDRA_VERSION}_PUBLIC/* /opt/ghidra/; \
    rm -rf /opt/ghidra_tmp ghidra.zip; \
    ln -s /opt/ghidra/support/analyzeHeadless /usr/local/bin/analyzeHeadless

# Build and install SNES toolchain (loader, processor, Sleigh compilation).
# Single monolithic RUN block: matches existing Ghidra install pattern and
# minimizes layer count. Cleanup (rm -rf /root/.gradle) must occur in the
# same layer to avoid persisting hundreds of MB in an intermediate layer. (DL-002, DL-010)
#
# All steps run as root (Ghidra install dir /opt/ghidra/ is root-owned).
#
# Nested extraction guard: unzip of ghidra-snes-loader can produce
# SnesLoader/SnesLoader/ when the ZIP contains a top-level directory;
# extension.properties depth is verified to prevent Ghidra silently
# ignoring the extension (no error is logged on version/path mismatch). (DL-003)
RUN set -eux; \
    # Clone and build SNES loader extension
    git clone --depth 1 https://github.com/ViewtifulSlayer/ghidra-snes-loader.git /tmp/ghidra-snes-loader; \
    cd /tmp/ghidra-snes-loader/SnesLoader; \
    GHIDRA_INSTALL_DIR=/opt/ghidra ./gradlew buildExtension; \
    # Extract loader ZIP into Extensions/SnesLoader/ (must not be nested)
    mkdir -p /opt/ghidra/Ghidra/Extensions/SnesLoader; \
    unzip -q dist/ghidra_*_SnesLoader.zip -d /opt/ghidra/Ghidra/Extensions/SnesLoader; \
    # Verify extension.properties is at correct depth (not nested SnesLoader/SnesLoader/)
    if [ ! -f /opt/ghidra/Ghidra/Extensions/SnesLoader/extension.properties ]; then \
        NESTED=$(find /opt/ghidra/Ghidra/Extensions/SnesLoader -name extension.properties | head -1); \
        if [ -z "$NESTED" ]; then \
            echo "ERROR: extension.properties not found after extraction"; exit 1; \
        fi; \
        NESTED_DIR=$(dirname "$NESTED"); \
        mv "$NESTED_DIR"/* /opt/ghidra/Ghidra/Extensions/SnesLoader/; \
        rm -rf "$NESTED_DIR"; \
    fi; \
    # Clone 65816 processor module (raw Sleigh, no Gradle)
    git clone --depth 1 https://github.com/ViewtifulSlayer/ghidra-65816.git /tmp/ghidra-65816; \
    cp -r /tmp/ghidra-65816 /opt/ghidra/Ghidra/Processors/65816; \
    # Pre-compile Sleigh spec (headless mode does not auto-compile .slaspec)
    /opt/ghidra/support/sleigh /opt/ghidra/Ghidra/Processors/65816/data/languages/65816.slaspec; \
    # Install SetSnesRegisters.java GhidraScript
    mkdir -p /opt/ghidra/Ghidra/Scripts; \
    # Clean up build artifacts and source repos to minimize image size
    rm -rf /tmp/ghidra-snes-loader /tmp/ghidra-65816 /root/.gradle \
           /opt/ghidra/Ghidra/Processors/65816/.git

# Copy SetSnesRegisters.java into the Ghidra Scripts directory
COPY resources/scripts/SetSnesRegisters.java /opt/ghidra/Ghidra/Scripts/SetSnesRegisters.java

# Install wrapper scripts for 16-bit x86 disassembly and SNES analysis
# snes-analyze reduces the 12+ token analyzeHeadless SNES invocation to a
# single command, following the dis16/r216/dump16 pattern. (DL-007)
COPY resources/scripts/dis16.sh /usr/local/bin/dis16
COPY resources/scripts/r216.sh /usr/local/bin/r216
COPY resources/scripts/dump16.sh /usr/local/bin/dump16
COPY resources/scripts/snes-analyze.sh /usr/local/bin/snes-analyze
RUN chmod +x /usr/local/bin/dis16 /usr/local/bin/r216 /usr/local/bin/dump16 /usr/local/bin/snes-analyze

# Create non-root user with matching UID/GID
RUN if [ "${USER_UID}" = "1000" ]; then \
        groupmod -n codeuser -g ${USER_GID} ubuntu && \
        usermod -d /home/codeuser -l codeuser -u ${USER_UID} -g codeuser ubuntu && \
        mv /home/ubuntu /home/codeuser; \
    else \
        groupadd -g ${USER_GID} codeuser && \
        useradd -m -d /home/codeuser -u ${USER_UID} -g ${USER_GID} -s /bin/bash codeuser; \
    fi

# Install uv for Python package management (as root for global availability)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:${PATH}"

# Switch to codeuser for the rest of the setup
USER codeuser
WORKDIR /home/codeuser

# Set up environment paths for codeuser
ENV PATH="/home/codeuser/.local/bin:/home/codeuser/.cargo/bin:${PATH}"

# Install Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV DISABLE_AUTOUPDATER=1

# After claude install completes:
RUN rm -f /home/codeuser/.claude.json

# Install uv for the user
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Python disassembly libraries
RUN pip install --break-system-packages capstone pefile

# Clone and set up Serena source (Software Installation)
RUN git clone https://github.com/oraios/serena.git

# Install Serena dependencies
WORKDIR /home/codeuser/serena
RUN uv venv && \
    . .venv/bin/activate && \
    uv pip install -r pyproject.toml -e .

# --- START: Runtime Provisioning Setup ---
# Switch to root to setup shared staging area
USER root

# Create a staging area for immutable config templates
RUN mkdir -p /usr/local/share/claude-env

# Copy Golden Master configurations directly
COPY resources/config/serena_config.yml /usr/local/share/claude-env/serena_config.yml
COPY resources/config/.bash_aliases /usr/local/share/claude-env/.bash_aliases

# Ensure codeuser can read these
RUN chown -R codeuser:codeuser /usr/local/share/claude-env

# Install bash aliases for codeuser (alias claude to always skip permissions)
USER codeuser
RUN cp /usr/local/share/claude-env/.bash_aliases /home/codeuser/.bash_aliases

# Cleanup: Ensure HOME is clean of any baked config to allow symlinking at runtime
RUN rm -rf /home/codeuser/.serena /home/codeuser/.claude
# --- END: Runtime Provisioning Setup ---

WORKDIR /home/codeuser

# Startup script for container initialization
COPY --chown=codeuser:codeuser resources/scripts/init-workspace.sh /home/codeuser/init-workspace.sh
RUN chmod +x /home/codeuser/init-workspace.sh

# Create and set working directory for projects (as root)
USER root
RUN mkdir -p /workspace && chown -R codeuser:codeuser /workspace

# Switch back to codeuser for runtime
USER codeuser
WORKDIR /workspace

# Set environment variables
ENV PATH="/home/codeuser/serena/.venv/bin:${PATH}"
ENV SERENA_HOME="/home/codeuser/serena"
ENV PYTHONUNBUFFERED=1
# Scripts dir consumed by snes-analyze -scriptPath; scripts are baked into
# the image at this path by the SNES toolchain RUN block. (DL-004, DL-007)
ENV GHIDRA_SCRIPTS_DIR="/opt/ghidra/Ghidra/Scripts"
# Projects dir points into /workspace (bind-mounted from host) so Ghidra
# project files persist across container restarts. Container runs with --rm
# so /opt paths would be lost on exit. (DL-006)
ENV GHIDRA_PROJECTS_DIR="/workspace/.ghidra-projects"

# Health check
# Verifies: ndisasm/r2/python callable; x86 Sleigh compiled (RISK-002
# non-regression: Ghidra 12.x must retain x86:LE:16:Real Mode:default);
# 65816 Sleigh compiled; SNES loader extracted at correct depth (Ghidra
# silently ignores extensions with wrong version or path -- no error logged). (DL-001, DL-009, RISK-002)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ndisasm -v && r2 -v && python --version && \
        test -f /opt/ghidra/Ghidra/Processors/x86/data/languages/x86-16.sla && \
        test -f /opt/ghidra/Ghidra/Processors/65816/data/languages/65816.sla && \
        test -f /opt/ghidra/Ghidra/Extensions/SnesLoader/extension.properties || exit 1

# Entry point that runs initialization
ENTRYPOINT ["/home/codeuser/init-workspace.sh"]
