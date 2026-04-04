FROM ubuntu:24.04
# clangd is auto-downloaded by Serena on first project index; no LSP install needed here. (DL-001)

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

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

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD claude --version && python --version || exit 1

# Entry point that runs initialization
ENTRYPOINT ["/home/codeuser/init-workspace.sh"]
