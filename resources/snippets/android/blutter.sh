#!/bin/bash
# blutter launcher installed as /usr/local/bin/blutter. blutter resolves its
# bin, build, dartsdk and packages directories from the real path of
# blutter.py; Dockerfile.android makes those four directories in /opt/blutter
# symlinks into ~/.cache/blutter, which launch.sh persists. The first run per
# target Dart version clones and builds the Dart SDK (network, several
# minutes). The mkdir keeps the symlinks from dangling when the cache mount
# starts empty.
set -eu

cache=/home/codeuser/.cache/blutter
mkdir -p "$cache/bin" "$cache/build" "$cache/dartsdk" "$cache/packages"

# The cli-tools venv supplies the capstone, pyelftools and requests modules
# that blutter.py imports.
exec /opt/cli-tools/.venv/bin/python /opt/blutter/blutter.py "$@"
