# CLAUDE.md

Configuration files copied into the Docker image as golden-master templates.

## Index

| File                          | Contents (WHAT)                                                                                         | Read When (WHEN)                                                         |
| ----------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `serena_config.java.yml`      | Serena config with explicit JDTLS language server (java variant)                                        | Changing Java LSP settings, JDTLS workspace path                         |
| `serena_config.java-angular.yml` | Serena config derived from serena_config.java.yml, same explicit jdtls entry, plus notes on the SolidLSP-managed angular LS and its subsumption/npm-install caveats (java-angular variant) | Read when changing java-angular LSP behavior or polyglot project caveats; keep the jdtls entry in sync with serena_config.java.yml |
| `serena_config.auto.yml`      | Serena config with no language_servers block; Serena SolidLSP auto-manages clangd (c, c-pico, 68k)     | Changing auto-language-server behavior                                   |
| `serena_config.disabled.yml`  | Serena config with language_servers: {} (empty); disables all LSPs (x86, snes binary analysis variants) | Disabling language servers for binary-only variants                      |
| `.bash_aliases`               | Shell alias: runs Claude Code with `--dangerously-skip-permissions`                                     | Modifying default Claude CLI flags, understanding container shell setup  |
| `managed-settings.json`       | Claude Code managed settings baked into `/etc/claude-code/` by Dockerfile.base: disables the Artifact tool (`enableArtifact: false` + `permissions.deny: ["Artifact"]`), denies WebFetch (`permissions.deny: ["WebFetch"]`, trafilatura in the cli-tools venv is the replacement) and the session-URL commit trailer (`attribution.sessionUrl: false`); outranks the persisted user settings.json | Adding container-wide Claude Code defaults that must survive the per-project `.claudeproject/.claude` mount and `/config` toggles |
