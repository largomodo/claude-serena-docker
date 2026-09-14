# claude-env container toolchain: java-docker

Same Tools rows as the java variant, plus a rootless Docker Engine.

## Tools (java-docker)

| Tool | What | Use when |
| --- | --- | --- |
| `java` `javac` `jar` | Temurin JDK 21 at /opt/java/openjdk | Compiling, running, or packaging Java code |
| `mvn` | Maven; `~/.m2` persisted across launches | Building or resolving dependencies for a Maven project |
| `jdtls` | Eclipse JDT-LS launcher used by Serena (2G heap) | Debugging Serena's Java language server startup |
| `docker` `dockerd-rootless.sh` | Engine CLI with `docker compose` plugin; rootless daemon started by the entrypoint | Building images, running Testcontainers, Quarkus Dev Services |

## Environment (java-docker)

| Variable | What |
| --- | --- |
| `VARIANT` | Container variant name (`java-docker`) |
| `JAVA_HOME` | JDK installation root |
| `DOCKER_HOST` | Rootless Docker daemon socket |
| `XDG_RUNTIME_DIR` | Runtime dir the rootless daemon uses for its socket |

## Notes (java-docker)

- Testcontainers and Quarkus Dev Services find the daemon through `DOCKER_HOST` with no extra config.
- Host-published ports are 8080 and 5005 only.
- Inner daemon storage persists in /workspace/.claudeproject/docker.
- Read /usr/local/share/claude-env/tools/java-docker-notes.md when running Quarkus dev mode, Testcontainers, or debugging container-died errors.
- Presence on PATH is what the build verifies; it does not guarantee a listed tool succeeds for every invocation.
