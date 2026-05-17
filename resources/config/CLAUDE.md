# CLAUDE.md

Configuration files copied into the Docker image as golden-master templates.

## Index

| File                          | Contents (WHAT)                                                                                         | Read When (WHEN)                                                         |
| ----------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `serena_config.java.yml`      | Serena config with explicit JDTLS language server (java variant)                                        | Changing Java LSP settings, JDTLS workspace path                         |
| `serena_config.auto.yml`      | Serena config with no language_servers block; Serena SolidLSP auto-manages clangd (c, c-pico, 68k)     | Changing auto-language-server behavior                                   |
| `serena_config.disabled.yml`  | Serena config with language_servers: {} (empty); disables all LSPs (x86, snes binary analysis variants) | Disabling language servers for binary-only variants                      |
| `.bash_aliases`               | Shell alias: runs Claude Code with `--dangerously-skip-permissions`                                     | Modifying default Claude CLI flags, understanding container shell setup  |
