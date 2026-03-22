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
ARG GHIDRA_VERSION=11.3.2
ARG GHIDRA_DATE=20250415
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
RUN set -eux; \
    mkdir -p /opt/ghidra; \
    wget -q -O ghidra.zip "${GHIDRA_URL}"; \
    unzip -q ghidra.zip -d /opt/ghidra_tmp; \
    mv /opt/ghidra_tmp/ghidra_${GHIDRA_VERSION}_PUBLIC/* /opt/ghidra/; \
    rm -rf /opt/ghidra_tmp ghidra.zip; \
    ln -s /opt/ghidra/support/analyzeHeadless /usr/local/bin/analyzeHeadless

# Install wrapper scripts for 16-bit x86 disassembly
COPY resources/scripts/dis16.sh /usr/local/bin/dis16
COPY resources/scripts/r216.sh /usr/local/bin/r216
COPY resources/scripts/dump16.sh /usr/local/bin/dump16
RUN chmod +x /usr/local/bin/dis16 /usr/local/bin/r216 /usr/local/bin/dump16

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

# Ensure codeuser can read these
RUN chown -R codeuser:codeuser /usr/local/share/claude-env

# Cleanup: Ensure HOME is clean of any baked config to allow symlinking at runtime
USER codeuser
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

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ndisasm -v && r2 -v && python --version || exit 1

# Entry point that runs initialization
ENTRYPOINT ["/home/codeuser/init-workspace.sh"]
