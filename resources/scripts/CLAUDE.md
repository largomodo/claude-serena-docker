# CLAUDE.md

Shell scripts that run inside the container at startup and runtime.

## Index

| File                | Contents (WHAT)                                                                                                                                     | Read When (WHEN)                                              |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `init-workspace.sh` | ENTRYPOINT: variant-aware init via VARIANT env var; populates bind-mounted dirs, session-exit `.claude.json` persistence, Serena indexing, MCP registration; for java-angular, creates a multi-language (polyglot) Serena project via MULTI_LANG collect-all detection with the angular-subsumes-typescript rule | Debugging container startup, changing init sequence, modifying variant-specific language detection, modifying multi-language detection |
| `start-dockerd.sh`  | ENTRYPOINT for the image-dev and java-docker variants; starts rootless `dockerd`, exports `DOCKER_HOST` derived from the runtime UID, polls for daemon readiness, then execs `init-workspace.sh`. Shared by both variants. | Debugging rootless Docker daemon startup, changing DinD readiness polling, modifying `DOCKER_HOST` resolution |
| `jdtls.sh`          | JDTLS launcher: workspace arg, 2G heap, JDK path (used by all Java-bearing variants: java, java-docker, java-angular)                               | Changing JDT Language Server settings, debugging JDTLS launch |
