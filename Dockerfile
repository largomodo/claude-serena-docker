FROM ubuntu:25.10
# clangd is auto-downloaded by Serena on first project index; no LSP install needed here.
# Ubuntu 25.10 (non-LTS, EOL July 2026) required for GCC 13+ Cortex-M33 support for RP2350 ARM. (DL-001)
# Accepted risk: Serena, clangd, or Node.js may break on 25.10; verify node/npm/Serena after base change. (RSK-007)

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# User configuration
ARG USER_UID=1000
ARG USER_GID=1000

# Pico toolchain version pins — override at build time without editing this file.
# OPENOCD_TAG pins to RPi fork sdk-2.2.0; upstream 0.12.0 has a sleep freeze bug and lacks RP2350 support. (DL-004, DL-007)
ARG PICO_SDK_TAG=2.2.0
ARG PICOTOOL_TAG=2.2.0
ARG OPENOCD_TAG=sdk-2.2.0
ARG RISCV_TOOLCHAIN_RELEASE=v2.2.0-3
ARG RISCV_TOOLCHAIN_ASSET=riscv-toolchain-15-x86_64-lin.tar.gz

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
    # Pico toolchain: build deps for picotool (cmake, libusb) and OpenOCD RPi fork (autotools, libhidapi, libftdi)
    cmake \
    gcc-arm-none-eabi \
    libnewlib-arm-none-eabi \
    libstdc++-arm-none-eabi-newlib \
    gdb-multiarch \
    minicom \
    pkg-config \
    libusb-1.0-0-dev \
    automake \
    autoconf \
    libtool \
    texinfo \
    libhidapi-dev \
    libftdi1-dev \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Create Python symlink for compatibility
RUN ln -sf /usr/bin/python3 /usr/bin/python

# Pico toolchain source builds run as root before USER codeuser because /opt and /usr/local
# require root ownership. All build artifacts are installed to /usr/local/bin (picotool, openocd)
# or /opt (pico-sdk, riscv-toolchain); codeuser needs only read access at runtime. (DL-003, DL-008)
# Single-stage build maintained: multi-stage adds complexity with no runtime benefit in a dev container. (DL-002)
# --- START: Pico toolchain source builds (as root, before USER codeuser) ---

# (1) Pico SDK: clone with submodules to /opt/pico-sdk (DL-003)
RUN git clone --depth 1 --branch ${PICO_SDK_TAG} --recurse-submodules \
        https://github.com/raspberrypi/pico-sdk.git /opt/pico-sdk && \
    chmod -R a+rX /opt/pico-sdk

# (2) Ubuntu ships gcc-riscv64-unknown-elf (wrong triple); pico-sdk CMake only recognises
# riscv32-corev-elf or riscv32-unknown-elf. The RPi prebuilt from pico-sdk-tools provides
# riscv32-corev-elf-gcc. Asset naming: corev-openhw-gcc-ubuntu-2404-x86_64-<tag>.tar.gz;
# x86_64 selects the host architecture (building for riscv32 target on x86_64 host). (DL-005, DL-011, RSK-003)
# The build fails if the binary is absent — guards against bootstrap/stub tarballs where
# the archive header is valid but contents are incomplete.
# (2) RISC-V prebuilt toolchain: download RPi prebuilt from pico-sdk-tools (DL-005, DL-011)
RUN mkdir -p /opt/riscv-toolchain && \
    curl -fsSL \
        "https://github.com/raspberrypi/pico-sdk-tools/releases/download/${RISCV_TOOLCHAIN_RELEASE}/${RISCV_TOOLCHAIN_ASSET}" \
        -o /tmp/riscv-toolchain.tar.gz && \
    tar -xzf /tmp/riscv-toolchain.tar.gz -C /opt/riscv-toolchain && \
    rm /tmp/riscv-toolchain.tar.gz && \
    if [ ! -x /opt/riscv-toolchain/bin/riscv32-unknown-elf-gcc ]; then \
        echo "ERROR: riscv32-unknown-elf-gcc not found in /opt/riscv-toolchain/bin" && \
        echo "The downloaded tarball may be a bootstrap/stub; check RISCV_TOOLCHAIN_RELEASE=${RISCV_TOOLCHAIN_RELEASE}" && \
        exit 1; \
    fi && \
    chmod -R a+rX /opt/riscv-toolchain

# (3) picotool: build from source against pico-sdk (DL-003)
RUN git clone --depth 1 --branch ${PICOTOOL_TAG} \
        https://github.com/raspberrypi/picotool.git /tmp/picotool-src && \
    cmake -S /tmp/picotool-src -B /tmp/picotool-build \
        -DPICO_SDK_PATH=/opt/pico-sdk \
        -DCMAKE_BUILD_TYPE=Release && \
    cmake --build /tmp/picotool-build --parallel $(nproc) && \
    cmake --install /tmp/picotool-build && \
    rm -rf /tmp/picotool-src /tmp/picotool-build

# (4) RPi OpenOCD fork sdk-2.2.0 includes rp2040.cfg, rp2350.cfg, rp2350-riscv.cfg, rp2350-rescue.cfg.
# --enable-cmsis-dap-v2 enables Picoprobe support. Upstream 0.12.0 lacks RP2350 and has a sleep freeze
# bug; only the RPi fork is used. (DL-004)
# (4) OpenOCD RPi fork: build from source at sdk-2.2.0 tag (DL-004)
RUN git clone --depth 1 --branch ${OPENOCD_TAG} \
        https://github.com/raspberrypi/openocd.git /tmp/openocd-src && \
    cd /tmp/openocd-src && \
    git submodule update --init && \
    ./bootstrap && \
    ./configure \
        --enable-cmsis-dap \
        --enable-cmsis-dap-v2 \
        --enable-internal-jimtcl \
        --disable-werror \
        --prefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/openocd-src

# --- END: Pico toolchain source builds ---

# Create non-root user with matching UID/GID
RUN if [ "${USER_UID}" = "1000" ]; then \
        groupmod -n codeuser -g ${USER_GID} ubuntu && \
        usermod -d /home/codeuser -l codeuser -u ${USER_UID} -g codeuser ubuntu && \
        mv /home/ubuntu /home/codeuser && \
        # dialout: serial port access (ttyACM); plugdev: USB programmer access (Pico BOOTSEL, debug probes). (DL-006)
        usermod -aG dialout,plugdev codeuser; \
    else \
        groupadd -g ${USER_GID} codeuser && \
        useradd -m -d /home/codeuser -u ${USER_UID} -g ${USER_GID} -s /bin/bash codeuser && \
        # dialout: serial port access (ttyACM); plugdev: USB programmer access (Pico BOOTSEL, debug probes). (DL-006)
        usermod -aG dialout,plugdev codeuser; \
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

# PICO_SDK_PATH: consumed by pico-sdk CMake toolchain files and picotool.
# PICO_RISCV_TOOLCHAIN_PATH: consumed by pico-sdk CMake to locate riscv32-unknown-elf-gcc.
# PICO_TOOLCHAIN_PATH is absent: setting it to the RISC-V path overrides the compiler
# search for ALL architectures, causing ARM builds to fail because pico-sdk CMake
# looks for arm-none-eabi-gcc inside that path instead of system PATH. The ARM toolchain
# (gcc-arm-none-eabi, installed via apt) is found via system PATH without any override. (DL-009)
# Pico SDK and RISC-V toolchain environment (DL-005, DL-008, DL-009)
ENV PICO_SDK_PATH=/opt/pico-sdk
ENV PICO_RISCV_TOOLCHAIN_PATH=/opt/riscv-toolchain
ENV PATH="/opt/riscv-toolchain/bin:${PATH}"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD claude --version && python --version || exit 1

# Entry point that runs initialization
ENTRYPOINT ["/home/codeuser/init-workspace.sh"]
