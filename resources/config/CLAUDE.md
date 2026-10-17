# CLAUDE.md

Configuration files copied into the Docker image as golden-master templates.

## Index

| File                          | Contents (WHAT)                                                                                         | Read When (WHEN)                                                         |
| ----------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `serena_config.java.yml`      | Serena v2 config for java, java-docker and java-angular; v2 keys only: REPL interface, dashboard on 0.0.0.0 without auto-open, /workspace trusted, ls_specific_settings.java (upstream JDTLS at /opt/jdtls, Lombok /opt/lombok/lombok.jar, 2G heap); project data placed under .claudeproject/serena (project_serena_folder_location), plus java-angular comments on the SolidLSP-managed angular LS and its subsumption/npm-install caveats | Changing dashboard, trust or interface settings for the Java variants, changing java-angular LSP behavior or polyglot project caveats |
| `serena_config.cpp.yml`       | Serena v2 config for c, c-pico and arduino; auto keys plus ls_specific_settings.cpp.ls_path /usr/bin/clangd (apt clangd); project data placed under .claudeproject/serena (project_serena_folder_location) | Changing the C/C++ language-server path for the C variants               |
| `serena_config.auto.yml`      | Serena v2 config for every other variant (68k, gowin, kicad, image-dev, x86, snes; x86/snes create no project); project data placed under .claudeproject/serena (project_serena_folder_location) | Changing dashboard, trust or interface settings for the remaining variants |
| `.bash_aliases`               | Shell alias: runs Claude Code with `--dangerously-skip-permissions`                                     | Modifying default Claude CLI flags, understanding container shell setup  |
| `managed-settings.json`       | Claude Code managed settings baked into `/etc/claude-code/` by Dockerfile.base: disables the Artifact tool (`enableArtifact: false` + `permissions.deny: ["Artifact"]`), denies WebFetch (`permissions.deny: ["WebFetch"]`, trafilatura in the cli-tools venv is the replacement) and the session-URL commit trailer (`attribution.sessionUrl: false`); outranks the persisted user settings.json | Adding container-wide Claude Code defaults that must survive the per-project `.claudeproject/.claude` mount and `/config` toggles |
