#!/bin/bash
# REA (rea-agents, https://github.com/morluto/rea) install shared by
# Dockerfile.x86 and Dockerfile.68k (pin from the x-rea-toolchain anchor in
# docker-compose.yml). REA is the MCP server and CLI that drives the baked
# Ghidra; init-workspace.sh registers it with Claude Code at launch
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
# Usage: install-rea.sh <rea_version>
#   e.g. install-rea.sh 6.7.0
set -eux

if [ $# -ne 1 ] || [ -z "$1" ]; then
    echo "Usage: $0 <rea_version>" >&2
    exit 2
fi

REA_VERSION="$1"
REA_PREFIX=/opt/rea
REA_PACKAGE="${REA_PREFIX}/lib/node_modules/rea-agents"

# `frida` is REA's only optional dependency: a 110 MB native agent for
# dynamic instrumentation that nothing in these images uses. npm 9 ignores
# --omit=optional for global installs (verified with the base image's npm
# 9.2), so the module is removed after the install; REA treats a missing
# optional dependency as "frida unavailable" and every Ghidra-backed command
# still works (verified: raw m68k and DOS COM analysis after removal).
npm install -g --prefix "${REA_PREFIX}" --omit=optional "rea-agents@${REA_VERSION}"
rm -rf "${REA_PACKAGE}/node_modules/frida"
npm cache clean --force
rm -rf /root/.npm

ln -s "${REA_PREFIX}/bin/rea" /usr/local/bin/rea

# The version check catches a dist-tag or range sneaking in through the
# pin; the skill check guards the path register_rea_mcp copies from.
test "$(/usr/local/bin/rea --version)" = "${REA_VERSION}"
test -f "${REA_PACKAGE}/skills/reverse-engineer-anything/SKILL.md"
test -f "${REA_PACKAGE}/bridge/ghidra/ReaGhidraBridge.java"
