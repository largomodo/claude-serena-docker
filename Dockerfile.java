ARG BASE_TAG=latest
FROM claude-env-base:${BASE_TAG}

USER root

# Java 21 LTS configuration
# Values come from the x-java-toolchain anchor in docker-compose.yml (single
# source of truth across java, java-docker, java-angular). (ref: DL-001)
# Builds go through
# ./build.sh -- a bare `docker build` has no versions and fails the guard below.
ARG JAVA_LANG_VERSION
ARG ADOPTIUM_VERSION
ARG ADOPTIUM_BUILD
ARG JDK_URL="https://github.com/adoptium/temurin${JAVA_LANG_VERSION}-binaries/releases/download/jdk-${ADOPTIUM_VERSION}%2B${ADOPTIUM_BUILD}/OpenJDK${JAVA_LANG_VERSION}U-jdk_x64_linux_hotspot_${ADOPTIUM_VERSION}_${ADOPTIUM_BUILD}.tar.gz"
ARG JDK_CHECKSUM_URL="https://github.com/adoptium/temurin${JAVA_LANG_VERSION}-binaries/releases/download/jdk-${ADOPTIUM_VERSION}%2B${ADOPTIUM_BUILD}/OpenJDK${JAVA_LANG_VERSION}U-jdk_x64_linux_hotspot_${ADOPTIUM_VERSION}_${ADOPTIUM_BUILD}.tar.gz.sha256.txt"

# Eclipse JDT LS configuration
ARG JDTLS_VERSION
ARG JDTLS_TIMESTAMP
ARG JDTLS_URL="http://download.eclipse.org/jdtls/milestones/${JDTLS_VERSION}/jdt-language-server-${JDTLS_VERSION}-${JDTLS_TIMESTAMP}.tar.gz"

# Lombok agent for JDT-LS upstream mode; the digest comes from the compose anchor.
ARG LOMBOK_VERSION
ARG LOMBOK_SHA256
ARG LOMBOK_URL="https://repo1.maven.org/maven2/org/projectlombok/lombok/${LOMBOK_VERSION}/lombok-${LOMBOK_VERSION}.jar"

# Fails fast on an out-of-compose build rather than silently drifting from
# the anchor with a stale default. (ref: DL-002)
RUN test -n "${JAVA_LANG_VERSION}" && test -n "${ADOPTIUM_VERSION}" && test -n "${ADOPTIUM_BUILD}" \
    && test -n "${JDTLS_VERSION}" && test -n "${JDTLS_TIMESTAMP}" \
    && test -n "${LOMBOK_VERSION}" && test -n "${LOMBOK_SHA256}" \
    || { echo "ERROR: Java toolchain ARGs unset -- build via ./build.sh (compose provides them)"; exit 1; }

RUN apt-get update && \
    apt-get install -y maven \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

RUN set -eux; \
    curl -L -o openjdk.tar.gz.sha256.txt "${JDK_CHECKSUM_URL}"; \
    sed -i 's/OpenJDK.*\.tar\.gz/openjdk.tar.gz/' openjdk.tar.gz.sha256.txt; \
    curl -L -o openjdk.tar.gz "${JDK_URL}"; \
    sha256sum -c openjdk.tar.gz.sha256.txt; \
    mkdir -p /opt/java/openjdk; \
    tar -zxvf openjdk.tar.gz -C /opt/java/openjdk --strip-components=1; \
    rm openjdk.tar.gz openjdk.tar.gz.sha256.txt

ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

RUN java -Xshare:dump 2>/dev/null || true

RUN set -eux; \
    mkdir -p /opt/jdtls; \
    wget -q -O jdtls.tar.gz "${JDTLS_URL}"; \
    tar -xzf jdtls.tar.gz -C /opt/jdtls; \
    rm jdtls.tar.gz

# Serena's upstream JDT-LS mode needs jdtls_path and lombok_path together;
# otherwise it downloads the vscode-java bundle into $SERENA_HOME. Lombok lives
# at /opt/lombok, beside /opt/jdtls, because ~/.m2 is bind-mounted at runtime
# and would shadow an image-side copy.
RUN set -eux; \
    mkdir -p /opt/lombok; \
    curl -fsSL -o /opt/lombok/lombok.jar "${LOMBOK_URL}"; \
    echo "${LOMBOK_SHA256}  /opt/lombok/lombok.jar" | sha256sum -c -

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
