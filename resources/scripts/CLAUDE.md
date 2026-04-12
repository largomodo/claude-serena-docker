# CLAUDE.md

Shell scripts that run inside the container at startup and runtime.

## Index

| File                | Contents (WHAT)                                                                                                    | Read When (WHEN)                                              |
| ------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| `init-workspace.sh` | ENTRYPOINT: populates bind-mounted dirs, session-exit `.claude.json` persistence, Serena indexing, MCP registration | Debugging container startup, changing init sequence           |
| `jdtls.sh`          | JDTLS launcher: workspace arg, 2G heap, JDK path                                                                   | Changing JDT Language Server settings, debugging JDTLS launch |
