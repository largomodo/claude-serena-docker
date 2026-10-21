#!/bin/bash
# Eclipse JDT-LS install shared by Dockerfile.java, java-docker and
# java-angular. The caller owns the version pins (x-java-toolchain anchor in
# docker-compose.yml, including the sha256 digest) and the chown to codeuser.
# (ref: DL-001 in plan-refactor-improvement-work-items.md)
#
# Usage: install-jdtls.sh <jdtls_version> <jdtls_timestamp> <jdtls_sha256>
# The download is always checksum-verified.
set -eux

if [ $# -ne 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: $0 <jdtls_version> <jdtls_timestamp> <jdtls_sha256>" >&2
    exit 2
fi

JDTLS_VERSION="$1"
JDTLS_TIMESTAMP="$2"
JDTLS_SHA256="$3"
JDTLS_URL="https://download.eclipse.org/jdtls/milestones/${JDTLS_VERSION}/jdt-language-server-${JDTLS_VERSION}-${JDTLS_TIMESTAMP}.tar.gz"
# The milestone directory carries the version; the timestamp suffix identifies
# the build within it and cannot be derived from the version, so both are pins.

mkdir -p /opt/jdtls
# The digest is pinned by the caller rather than fetched from the .sha256 file
# beside the tarball: that file shares the tarball's origin, so it would not
# detect a tampered download.
curl -fsSL -o jdtls.tar.gz "${JDTLS_URL}"
echo "${JDTLS_SHA256}  jdtls.tar.gz" | sha256sum -c -
# --no-same-owner: the Eclipse tarball carries owner uids around 1001380000,
# which a user-namespaced (rootless Docker-in-Docker) daemon cannot chown to,
# so extraction as root fails there without it. The caller chowns /opt/jdtls
# to codeuser afterwards, so the flag is neutral on root daemons. (ref: DL-003 in plan-refactor-improvement-work-items.md)
tar -xzf jdtls.tar.gz --no-same-owner -C /opt/jdtls
rm jdtls.tar.gz
