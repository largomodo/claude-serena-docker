#!/bin/bash
set -e

if [ $# -eq 0 ]; then
    echo 'Usage: dis16 <binary_file> [ndisasm options]'
    echo 'Disassembles binary as 16-bit x86 real mode using ndisasm.'
    exit 1
fi
exec ndisasm -b 16 "$@"
