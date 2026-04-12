# CLAUDE.md

Config templates and shell scripts copied into the Docker image at build time.

## Index

| Directory  | Contents (WHAT)                                    | Read When (WHEN)                                                    |
| ---------- | -------------------------------------------------- | ------------------------------------------------------------------- |
| `config/`  | Serena config template, shell aliases              | Changing Serena behavior, dashboard address, modifying shell aliases |
| `scripts/` | Container ENTRYPOINT, JDTLS launcher, and Tier 3 on-demand install script | Debugging container startup, changing init sequence, modifying JDTLS, adding or modifying Tier 3 on-demand tool installs |
