#!/bin/bash
# Ghidra install shared by Dockerfile.x86, Dockerfile.snes and Dockerfile.68k
# (pins from the x-ghidra-toolchain anchor in docker-compose.yml). The script
# owns the download, checksum verification and layout; each caller passes its
# pins as arguments, same contract as install-jdk.sh. The NSA publishes no
# checksum sidecar for the release zip, so the digest is a pinned argument
# and an empty one fails here before any download.
# Callers run it as `bash install-ghidra.sh ...` (see install-jdk.sh for why).
# Result: /opt/ghidra owned by codeuser, analyzeHeadless on PATH. A RUN
# process cannot change image ENV, so the caller sets GHIDRA_INSTALL_DIR
# itself (REA's Ghidra provider reads it; nothing else needs it).
#
# Usage: install-ghidra.sh <ghidra_version> <ghidra_date> <ghidra_sha256>
#   e.g. install-ghidra.sh 12.1.4 20260921 ddac49f9...
set -eux

if [ $# -ne 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: $0 <ghidra_version> <ghidra_date> <ghidra_sha256>" >&2
    echo "The Ghidra download is always checksum-verified; keep the pinned digest or pass the digest for the release you pin." >&2
    exit 2
fi

GHIDRA_VERSION="$1"
GHIDRA_DATE="$2"
GHIDRA_SHA256="$3"

GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_DATE}.zip"

curl -L -o /tmp/ghidra.zip "${GHIDRA_URL}"
echo "${GHIDRA_SHA256}  /tmp/ghidra.zip" | sha256sum -c -
unzip -q /tmp/ghidra.zip -d /opt
# The zip's versioned top directory is renamed to the fixed path every
# caller, tool sheet and GHIDRA_INSTALL_DIR names.
mv "/opt/ghidra_${GHIDRA_VERSION}_PUBLIC" /opt/ghidra
rm /tmp/ghidra.zip
ln -s /opt/ghidra/support/analyzeHeadless /usr/local/bin/analyzeHeadless
chown -R codeuser:codeuser /opt/ghidra
