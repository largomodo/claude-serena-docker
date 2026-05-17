#!/bin/bash
set -e

if [ $# -eq 0 ]; then
    echo "Usage: dump16 <file> [extra objdump args]" >&2
    exit 1
fi
exec objdump -m i8086 -M intel -b binary -D "$@"
