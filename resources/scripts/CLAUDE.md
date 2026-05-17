# CLAUDE.md

Shell scripts that run inside the container at startup and runtime.

## Index

| File                | Contents (WHAT)                                                                                                                                     | Read When (WHEN)                                              |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `init-workspace.sh` | ENTRYPOINT: variant-aware init via VARIANT env var; populates bind-mounted dirs, session-exit `.claude.json` persistence, Serena indexing, MCP registration | Debugging container startup, changing init sequence, modifying variant-specific language detection |
| `jdtls.sh`          | JDTLS launcher: workspace arg, 2G heap, JDK path (used by java variant only)                                                                        | Changing JDT Language Server settings, debugging JDTLS launch |
