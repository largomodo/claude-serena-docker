ARG BASE_TAG=latest
FROM claude-env-base:${BASE_TAG}

USER root

# build-essential in base already provides gcc/g++/make. clangd is Serena's
# C/C++ language server, referenced by ls_path in serena_config.cpp.yml; it
# is installed outside $SERENA_HOME, which the runtime bind mount shadows.
# apt tracks the Ubuntu clangd (21.x), not Serena's pinned 19.1.2; chosen for
# determinism and check-tools.sh visibility.
RUN apt-get update && \
    apt-get install -y --no-install-recommends clangd \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY resources/config/serena_config.cpp.yml /usr/local/share/claude-env/serena_config.yml
RUN chown codeuser:codeuser /usr/local/share/claude-env/serena_config.yml

# Tool sheet: concatenated with base.md and verified by check-tools.sh.
COPY --chown=codeuser:codeuser resources/tools/c.md /usr/local/share/claude-env/tools/c.md

USER codeuser

ENV VARIANT=c

# The sheet is imported into every agent session via ~/.claude/claude-env.md;
# the check keeps it honest. Must stay the last RUN, after USER codeuser and
# after every ENV line, so the check sees VARIANT.
RUN cat /usr/local/share/claude-env/tools/base.md /usr/local/share/claude-env/tools/c.md > /usr/local/share/claude-env/claude-env.md && \
    check-tools.sh /usr/local/share/claude-env/claude-env.md

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD claude --version && python --version || exit 1
