ARG BASE_TAG=latest
FROM claude-env-base:${BASE_TAG}

USER root

# Java 21 LTS configuration
ARG JAVA_LANG_VERSION=21
ARG ADOPTIUM_VERSION=21.0.10
ARG ADOPTIUM_BUILD=7
ARG JDK_URL="https://github.com/adoptium/temurin${JAVA_LANG_VERSION}-binaries/releases/download/jdk-${ADOPTIUM_VERSION}%2B${ADOPTIUM_BUILD}/OpenJDK${JAVA_LANG_VERSION}U-jdk_x64_linux_hotspot_${ADOPTIUM_VERSION}_${ADOPTIUM_BUILD}.tar.gz"
ARG JDK_CHECKSUM_URL="https://github.com/adoptium/temurin${JAVA_LANG_VERSION}-binaries/releases/download/jdk-${ADOPTIUM_VERSION}%2B${ADOPTIUM_BUILD}/OpenJDK${JAVA_LANG_VERSION}U-jdk_x64_linux_hotspot_${ADOPTIUM_VERSION}_${ADOPTIUM_BUILD}.tar.gz.sha256.txt"

# Eclipse JDT LS configuration
ARG JDTLS_VERSION=1.58.0
ARG JDTLS_TIMESTAMP=202604151538
ARG JDTLS_URL="http://download.eclipse.org/jdtls/milestones/${JDTLS_VERSION}/jdt-language-server-${JDTLS_VERSION}-${JDTLS_TIMESTAMP}.tar.gz"

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

COPY resources/scripts/jdtls.sh /usr/local/bin/jdtls
RUN chmod +x /usr/local/bin/jdtls

RUN chown -R codeuser:codeuser /opt/jdtls

COPY resources/config/serena_config.java.yml /usr/local/share/claude-env/serena_config.yml
RUN chown codeuser:codeuser /usr/local/share/claude-env/serena_config.yml

USER codeuser

ENV VARIANT=java

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD claude --version && java --version && python --version || exit 1
