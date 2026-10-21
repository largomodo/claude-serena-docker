ARG BASE_TAG=latest
FROM claude-env-base:${BASE_TAG}

USER root

# Java 25 LTS configuration
# Values come from the x-java-toolchain anchor in docker-compose.yml (single
# source of truth across java, java-docker, java-angular). (ref: DL-001)
# Builds go through
# ./build.sh -- a bare `docker build` has no versions and fails the guard below.
# The URL templates and install procedure live in the shared scripts under
# resources/snippets/shared; this file owns only the pins.
ARG JAVA_LANG_VERSION
ARG ADOPTIUM_VERSION
ARG ADOPTIUM_BUILD

# Eclipse JDT LS configuration
ARG JDTLS_VERSION
ARG JDTLS_TIMESTAMP
# JDTLS_SHA256 is pinned in the compose anchor: the .sha256 file beside the tarball shares its origin.
ARG JDTLS_SHA256

# Lombok agent for JDT-LS upstream mode; the digest comes from the compose anchor.
ARG LOMBOK_VERSION
ARG LOMBOK_SHA256

# Fails fast on an out-of-compose build rather than silently drifting from
# the anchor with a stale default. (ref: DL-002)
RUN test -n "${JAVA_LANG_VERSION}" && test -n "${ADOPTIUM_VERSION}" && test -n "${ADOPTIUM_BUILD}" \
    && test -n "${JDTLS_VERSION}" && test -n "${JDTLS_TIMESTAMP}" && test -n "${JDTLS_SHA256}" \
    && test -n "${LOMBOK_VERSION}" && test -n "${LOMBOK_SHA256}" \
    || { echo "ERROR: Java toolchain ARGs unset -- build via ./build.sh (compose provides them)"; exit 1; }

# apt maven depends on openjdk-25-jre-headless, which installs under
# /usr/lib/jvm. The Temurin JDK at /opt/java/openjdk is the only javac JDK;
# the ENV PATH line below keeps it first so `java` resolves to Temurin.
RUN apt-get update && \
    apt-get install -y maven \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Plain COPY then RUN keeps the scripts in the image under /usr/local/share/claude-env/install/
# and avoids BuildKit-only syntax (bind-mount RUN) so any builder works.
COPY resources/snippets/shared/install-jdk.sh resources/snippets/shared/install-jdtls.sh resources/snippets/shared/install-lombok.sh /usr/local/share/claude-env/install/

# Bash invocation and the ENV lines below: see the install-jdk.sh header.
RUN bash /usr/local/share/claude-env/install/install-jdk.sh "${JAVA_LANG_VERSION}" "${ADOPTIUM_VERSION}" "${ADOPTIUM_BUILD}"

ENV JAVA_HOME=/opt/java/openjdk
# Shadows the apt-pulled openjdk-25-jre-headless (/usr/lib/jvm) on PATH.
ENV PATH="${JAVA_HOME}/bin:${PATH}"

RUN bash /usr/local/share/claude-env/install/install-jdtls.sh "${JDTLS_VERSION}" "${JDTLS_TIMESTAMP}" "${JDTLS_SHA256}"

# Serena's upstream JDT-LS mode needs jdtls_path and lombok_path together;
# otherwise it downloads the vscode-java bundle into $SERENA_HOME. Lombok lives
# at /opt/lombok, beside /opt/jdtls, because ~/.m2 is bind-mounted at runtime
# and would shadow an image-side copy.
# Upstream mode globs the equinox launcher jar and uses config_linux under jdtls_path.
RUN bash /usr/local/share/claude-env/install/install-lombok.sh "${LOMBOK_VERSION}" "${LOMBOK_SHA256}"

RUN chown -R codeuser:codeuser /opt/jdtls /opt/lombok

COPY resources/config/serena_config.java.yml /usr/local/share/claude-env/serena_config.yml
RUN chown codeuser:codeuser /usr/local/share/claude-env/serena_config.yml

# Tool sheet: concatenated with base.md and verified by check-tools.sh.
COPY --chown=codeuser:codeuser resources/tools/java.md /usr/local/share/claude-env/tools/java.md

USER codeuser

ENV VARIANT=java

# The concatenated sheet is imported into every agent session via
# ~/.claude/claude-env.md; the check keeps it honest. Must stay the last
# RUN, after USER codeuser and after every ENV line, so the check sees
# VARIANT.
RUN cat /usr/local/share/claude-env/tools/base.md /usr/local/share/claude-env/tools/java.md > /usr/local/share/claude-env/claude-env.md && \
    check-tools.sh /usr/local/share/claude-env/claude-env.md

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD claude --version && java --version && python --version || exit 1
