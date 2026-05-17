ARG BASE_TAG=latest
FROM claude-env-base:${BASE_TAG}

USER root

# build-essential in base already provides gcc/g++/make; no additional apt packages needed.
COPY resources/config/serena_config.auto.yml /usr/local/share/claude-env/serena_config.yml
RUN chown codeuser:codeuser /usr/local/share/claude-env/serena_config.yml

USER codeuser

ENV VARIANT=c

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD claude --version && python --version || exit 1
