# CLAUDE.md

Wrapper scripts for the android variant, COPY'd to /usr/local/bin by Dockerfile.android.

The wrappers carry no pins: versions and digests live only in the android service of docker-compose.yml, so a bump edits one file.

## Index

| File | Contents (WHAT) | Read When (WHEN) |
| ---- | --------------- | ---------------- |
| `apktool.sh` | Apktool launcher (`/usr/local/bin/apktool`): -J passthrough, java options of upstream's wrapper, runs /opt/apktool/apktool.jar; REA_APKTOOL_COMMAND points here | Changing Apktool JVM options or the Apktool pin |
| `blutter.sh` | blutter launcher (`/usr/local/bin/blutter`): creates the ~/.cache/blutter subdirs the /opt/blutter symlinks target, runs blutter.py with the cli-tools Python; Dart SDK builds land in the cache, not the image | Changing the blutter cache layout, a blutter first-run failure |
| `il2cppdumper.sh` | Il2CppDumper launcher (`/usr/local/bin/il2cppdumper`): runs the net7 DLL on .NET 10 with DOTNET_ROLL_FORWARD=Major | Changing the .NET roll-forward, Il2CppDumper failures |
