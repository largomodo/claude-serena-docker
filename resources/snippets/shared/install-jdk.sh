#!/bin/bash
# Temurin JDK install shared by Dockerfile.java, java-docker, java-angular
# (versions from the x-java-toolchain anchor in docker-compose.yml) and by
# x86, snes, 68k and kicad (JDK 25 ARG defaults in each Dockerfile). snes
# additionally installs a JDK 21 into a temporary target_dir for its Gradle
# 8.5 build and deletes it in the same RUN. The script owns the procedure;
# each caller owns its pins and passes them as arguments.
# Callers run it as `bash install-jdk.sh ...`, so the build depends neither on
# the file mode COPY preserves nor on a chmod layer. A RUN process cannot
# change image ENV, so each Dockerfile sets JAVA_HOME and PATH itself after
# the call (also for the throwaway install: target_dir is only a location).
# The same applies to install-jdtls.sh and install-lombok.sh.
# (ref: DL-001 in plan-refactor-improvement-work-items.md, DL-002 in plan-refactor-improvement-work-items.md)
#
# Usage: install-jdk.sh <java_lang_version> <adoptium_version> <adoptium_build> [target_dir]
#   e.g. install-jdk.sh 25 25.0.4.1 1
#        install-jdk.sh 21 21.0.12.1 1 /tmp/gradle-jdk
set -eux

if { [ $# -ne 3 ] && [ $# -ne 4 ]; } || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || { [ $# -eq 4 ] && [ -z "$4" ]; }; then
    echo "Usage: $0 <java_lang_version> <adoptium_version> <adoptium_build> [target_dir]" >&2
    exit 2
fi

JAVA_LANG_VERSION="$1"
ADOPTIUM_VERSION="$2"
ADOPTIUM_BUILD="$3"
TARGET_DIR="${4:-/opt/java/openjdk}"
# Only the throwaway Gradle JDK in Dockerfile.snes passes a target_dir; every other caller takes the default.

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
mkdir -p "${TARGET_DIR}"
# --strip-components=1 drops the archive's versioned top directory so the JDK
# lands directly in TARGET_DIR (default /opt/java/openjdk, the path JAVA_HOME names).
tar -zxvf openjdk.tar.gz -C "${TARGET_DIR}" --strip-components=1
rm openjdk.tar.gz openjdk.tar.gz.sha256.txt

# Class-data-sharing archive for faster JVM start; a failed dump is harmless.
# The dump runs in the same layer as the download: it changes only when the
# JDK does, so a separate layer would never be reused independently. The
# cost is a re-download when only this step is edited.
"${TARGET_DIR}/bin/java" -Xshare:dump 2>/dev/null || true
