#!/bin/bash
# Temurin JDK install shared by Dockerfile.java, java-docker, java-angular
# (versions from the x-java-toolchain anchor in docker-compose.yml), x86 and
# snes (JDK 21 ARG defaults) and kicad (JDK 25 ARG defaults). The script owns
# the procedure; each caller owns its pins and passes them as arguments.
# Callers run it as `bash install-jdk.sh ...`, so the build depends neither on
# the file mode COPY preserves nor on a chmod layer. A RUN process cannot
# change image ENV, so each Dockerfile sets JAVA_HOME and PATH itself after
# the call. The same applies to install-jdtls.sh and install-lombok.sh.
# (ref: DL-001 in plan-refactor-improvement-work-items.md, DL-002 in plan-refactor-improvement-work-items.md)
#
# Usage: install-jdk.sh <java_lang_version> <adoptium_version> <adoptium_build>
#   e.g. install-jdk.sh 21 21.0.10 7
set -eux

if [ $# -ne 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: $0 <java_lang_version> <adoptium_version> <adoptium_build>" >&2
    exit 2
fi

JAVA_LANG_VERSION="$1"
ADOPTIUM_VERSION="$2"
ADOPTIUM_BUILD="$3"

JDK_BASE_URL="https://github.com/adoptium/temurin${JAVA_LANG_VERSION}-binaries/releases/download/jdk-${ADOPTIUM_VERSION}%2B${ADOPTIUM_BUILD}"
JDK_ASSET="OpenJDK${JAVA_LANG_VERSION}U-jdk_x64_linux_hotspot_${ADOPTIUM_VERSION}_${ADOPTIUM_BUILD}.tar.gz"
JDK_URL="${JDK_BASE_URL}/${JDK_ASSET}"
JDK_CHECKSUM_URL="${JDK_URL}.sha256.txt"

# The publisher's sidecar names the original asset; rewrite it to the local
# file name so sha256sum -c finds the download.
curl -L -o openjdk.tar.gz.sha256.txt "${JDK_CHECKSUM_URL}"
sed -i 's/OpenJDK.*\.tar\.gz/openjdk.tar.gz/' openjdk.tar.gz.sha256.txt
curl -L -o openjdk.tar.gz "${JDK_URL}"
sha256sum -c openjdk.tar.gz.sha256.txt
mkdir -p /opt/java/openjdk
# --strip-components=1 drops the archive's versioned top directory so the JDK
# lands directly in /opt/java/openjdk, the fixed path JAVA_HOME names.
tar -zxvf openjdk.tar.gz -C /opt/java/openjdk --strip-components=1
rm openjdk.tar.gz openjdk.tar.gz.sha256.txt

# Class-data-sharing archive for faster JVM start; a failed dump is harmless.
# The dump runs in the same layer as the download: it changes only when the
# JDK does, so a separate layer would never be reused independently. The
# cost is a re-download when only this step is edited.
/opt/java/openjdk/bin/java -Xshare:dump 2>/dev/null || true
