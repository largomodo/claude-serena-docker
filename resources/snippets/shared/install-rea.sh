#!/bin/bash
# REA (rea-agents, https://github.com/morluto/rea) install shared by
# Dockerfile.x86, Dockerfile.68k (frida removed) and Dockerfile.android (frida
# kept) (pin from the x-rea-toolchain anchor in docker-compose.yml). REA is
# the MCP server and CLI that drives the baked Ghidra; init-workspace.sh
# registers it with Claude Code at launch
# (register_rea_mcp) and copies the bundled skill into ~/.claude/skills.
#
# A global npm install into its own prefix keeps REA's node_modules out of
# the base image's /usr/lib/node_modules, and the pinned version makes the
# image reproducible: `rea update` is deliberately unsupported (the prefix is
# root-owned, like Serena's clone); bump REA_VERSION and rebuild instead.
# The npm cache is cleared because the ~400 MB of tarballs would otherwise
# stay in the layer. Node and npm come from the base image (Ubuntu apt Node
# 22, inside REA's declared engine range).
#
# Usage: install-rea.sh <rea_version> [keep-frida]
#   e.g. install-rea.sh 6.7.0
#        install-rea.sh 6.7.0 keep-frida
set -eux

if [ $# -lt 1 ] || [ $# -gt 2 ] || [ -z "$1" ] \
    || { [ $# -eq 2 ] && [ "$2" != "keep-frida" ]; }; then
    echo "Usage: $0 <rea_version> [keep-frida]" >&2
    exit 2
fi

REA_VERSION="$1"
# keep-frida is opt-in so the one-argument form used by x86 and 68k keeps
# deleting the module; any other second argument is a usage error rather
# than a silent default.
KEEP_FRIDA=false
if [ $# -eq 2 ]; then
    KEEP_FRIDA=true
fi
REA_PREFIX=/opt/rea
REA_PACKAGE="${REA_PREFIX}/lib/node_modules/rea-agents"

# `frida` is REA's only optional dependency: a 110 MB native agent for
# dynamic instrumentation that the x86 and 68k images do not use. npm 9
# ignores --omit=optional for global installs (verified with the base image's
# npm 9.2), so the module is removed after the install; REA treats a missing
# optional dependency as "frida unavailable" and every Ghidra-backed command
# still works (verified: raw m68k and DOS COM analysis after removal). The
# android image passes keep-frida because REA's Frida provider needs the
# module.
npm install -g --prefix "${REA_PREFIX}" --omit=optional "rea-agents@${REA_VERSION}"
if [ "${KEEP_FRIDA}" = true ]; then
    test -f "${REA_PACKAGE}/node_modules/frida/package.json"
else
    rm -rf "${REA_PACKAGE}/node_modules/frida"
fi
npm cache clean --force
rm -rf /root/.npm

ln -s "${REA_PREFIX}/bin/rea" /usr/local/bin/rea

# The version check catches a dist-tag or range sneaking in through the
# pin; the skill check guards the path register_rea_mcp copies from.
test "$(/usr/local/bin/rea --version)" = "${REA_VERSION}"
test -f "${REA_PACKAGE}/skills/reverse-engineer-anything/SKILL.md"
test -f "${REA_PACKAGE}/bridge/ghidra/ReaGhidraBridge.java"
