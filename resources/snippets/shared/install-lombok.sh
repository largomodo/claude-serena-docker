#!/bin/bash
# Lombok agent install shared by Dockerfile.java, java-docker and java-angular.
# (ref: DL-001 in plan-refactor-improvement-work-items.md)
#
# Serena's upstream JDT-LS mode needs jdtls_path and lombok_path together;
# otherwise it downloads the vscode-java bundle into $SERENA_HOME. Lombok lives
# at /opt/lombok, beside /opt/jdtls, because ~/.m2 is bind-mounted at runtime
# and would shadow an image-side copy. Maven Central publishes no .sha256 file,
# so the digest is recorded by hand in the compose x-java-toolchain anchor and
# passed in; the check is unconditional.
#
# Usage: install-lombok.sh <lombok_version> <lombok_sha256>
set -eux

if [ $# -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <lombok_version> <lombok_sha256>" >&2
    exit 2
fi

LOMBOK_VERSION="$1"
LOMBOK_SHA256="$2"
LOMBOK_URL="https://repo1.maven.org/maven2/org/projectlombok/lombok/${LOMBOK_VERSION}/lombok-${LOMBOK_VERSION}.jar"

mkdir -p /opt/lombok
# -f turns an HTTP error into a build failure instead of saving an error page
# for the checksum to reject.
curl -fsSL -o /opt/lombok/lombok.jar "${LOMBOK_URL}"
echo "${LOMBOK_SHA256}  /opt/lombok/lombok.jar" | sha256sum -c -
