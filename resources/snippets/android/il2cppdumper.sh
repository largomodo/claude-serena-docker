#!/bin/bash
# Il2CppDumper launcher installed as /usr/local/bin/il2cppdumper. The release
# targets net7 and Ubuntu 26.04 apt ships only dotnet-runtime-10.0, so the
# assembly runs through roll-forward. config.json has RequireAnyKey=false, so
# the dumper never waits on stdin.
set -eu

# Major lets the net7 assembly start on the only runtime Ubuntu ships.
export DOTNET_ROLL_FORWARD=Major
exec dotnet /opt/il2cppdumper/Il2CppDumper.dll "$@"
