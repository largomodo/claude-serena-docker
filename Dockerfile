FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Java 25 LTS configuration
ARG JAVA_LANG_VERSION=25
ARG ADOPTIUM_VERSION=25.0.1
ARG ADOPTIUM_BUILD=8
ARG JDK_URL="https://github.com/adoptium/temurin${JAVA_LANG_VERSION}-binaries/releases/download/jdk-${ADOPTIUM_VERSION}%2B${ADOPTIUM_BUILD}/OpenJDK${JAVA_LANG_VERSION}U-jdk_x64_linux_hotspot_${ADOPTIUM_VERSION}_${ADOPTIUM_BUILD}.tar.gz"
ARG JDK_CHECKSUM_URL="https://github.com/adoptium/temurin${JAVA_LANG_VERSION}-binaries/releases/download/jdk-${ADOPTIUM_VERSION}%2B${ADOPTIUM_BUILD}/OpenJDK${JAVA_LANG_VERSION}U-jdk_x64_linux_hotspot_${ADOPTIUM_VERSION}_${ADOPTIUM_BUILD}.tar.gz.sha256.txt"

# Eclipse JDT LS configuration
ARG JDTLS_VERSION=1.54.0
ARG JDTLS_TIMESTAMP=202511261751
ARG JDTLS_URL="http://download.eclipse.org/jdtls/milestones/${JDTLS_VERSION}/jdt-language-server-${JDTLS_VERSION}-${JDTLS_TIMESTAMP}.tar.gz"

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
    # Java build tools
    maven \
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

# Download and install Temurin OpenJDK 25 LTS
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

# Download and install Eclipse JDT Language Server
RUN set -eux; \
    mkdir -p /opt/jdtls; \
    # Download the jdtls tarball
    wget -q -O jdtls.tar.gz "${JDTLS_URL}"; \
    # Extract the archive
    tar -xzf jdtls.tar.gz -C /opt/jdtls; \
    # Clean up the downloaded file
    rm jdtls.tar.gz

# Create JDT LS launcher script
COPY resources/scripts/jdtls.sh /usr/local/bin/jdtls
RUN chmod +x /usr/local/bin/jdtls

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

# Install Claude Code globally
# old: v2.0.76
RUN npm install -g @anthropic-ai/claude-code

# Ensure codeuser owns the JDTLS installation to allow writing logs/config
RUN chown -R codeuser:codeuser /opt/jdtls

# Switch to codeuser for the rest of the setup
USER codeuser
WORKDIR /home/codeuser

# Set up environment paths for codeuser
ENV PATH="/home/codeuser/.local/bin:/home/codeuser/.cargo/bin:${PATH}"

# Install uv for the user
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

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
    CMD node --version && java --version && python --version || exit 1

# Entry point that runs initialization
ENTRYPOINT ["/home/codeuser/init-workspace.sh"]
