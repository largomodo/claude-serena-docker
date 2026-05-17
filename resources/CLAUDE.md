# CLAUDE.md

Config templates and shell scripts copied into the Docker image at build time.

## Index

| Directory    | Contents (WHAT)                                                                                         | Read When (WHEN)                                                                          |
| ------------ | ------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `config/`    | Variant Serena configs (java/auto/disabled) and shell aliases                                           | Changing Serena behavior, dashboard address, modifying shell aliases                       |
| `scripts/`   | Container ENTRYPOINT (variant-aware), JDTLS launcher, and Tier 3 on-demand install script              | Debugging container startup, changing init sequence, modifying JDTLS                       |
| `snippets/`  | Variant-specific Dockerfile resources organized by variant name (snes/, shared/)                        | Adding variant-specific resources, changing Dockerfile COPY paths for variants             |
