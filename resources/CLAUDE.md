# CLAUDE.md

Config templates and shell scripts copied into the Docker image at build time.

## Index

| Directory    | Contents (WHAT)                                                                                         | Read When (WHEN)                                                                          |
| ------------ | ------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `config/`    | Variant Serena configs (java/java-angular/cpp/auto) and shell aliases                                           | Changing Serena behavior, dashboard address, modifying shell aliases                       |
| `scripts/`   | Container ENTRYPOINTs (variant-aware), build-time guards, runtime helpers, KiCad autoroute tools              | Debugging container startup, changing init sequence                       |
| `snippets/`  | Variant-specific Dockerfile resources organized by variant name (snes/, shared/)                        | Adding variant-specific resources, changing Dockerfile COPY paths for variants             |
| `tools/`     | Per-variant tool sheets (base.md + <variant>.md) and notes files that are concatenated into the image and imported into every Claude Code session as ~/.claude/claude-env.md; format contract in tools/README.md | Adding or removing a tool or env var in any Dockerfile, changing what agents know about the container, a build failing at check-tools.sh |
| `udev/`      | Host-side udev rules for USB hardware access (Tang Nano 4K VID:PID pairs)                              | Modifying USB device permissions, adding support for new Tang Nano board revisions         |
