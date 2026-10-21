# claude-env container toolchain: java-docker

Same Tools rows as the java variant, plus a rootless Docker Engine.

## Tools (java-docker)

| Tool | What | Use when |
| --- | --- | --- |
| `java` `javac` `jar` | Temurin JDK 25 at /opt/java/openjdk | Compiling, running, or packaging Java code |
| `mvn` | Maven; `~/.m2` persisted across launches | Building or resolving dependencies for a Maven project |
| `docker` `dockerd-rootless.sh` | Engine CLI with `docker compose` plugin; rootless daemon started by the entrypoint | Building images, running Testcontainers, Quarkus Dev Services |

## Environment (java-docker)

| Variable | What |
| --- | --- |
| `VARIANT` | Container variant name (`java-docker`) |
| `JAVA_HOME` | JDK installation root |
| `DOCKER_HOST` | Rootless Docker daemon socket |
| `XDG_RUNTIME_DIR` | Runtime dir the rootless daemon uses for its socket |

## Notes (java-docker)

- Serena runs JDT-LS from /opt/jdtls in upstream mode (2G heap, Lombok at /opt/lombok/lombok.jar).
- Testcontainers and Quarkus Dev Services find the daemon through `DOCKER_HOST` with no extra config.
- apt Maven on JDK 25 prints `sun.misc.Unsafe` deprecation WARNING lines from its bundled guava; they are cosmetic and do not indicate a build failure.
- JDT-LS needs a Java 21 or newer runtime and runs on this JDK 25.
- Lombok 1.18.48 supports JDK 25, so annotation processing works under the image JDK.
- Host-published ports are 8080 and 5005 only.
- Inner daemon storage persists in /workspace/.claudeproject/docker.
- Read /usr/local/share/claude-env/tools/java-docker-notes.md when running Quarkus dev mode, Testcontainers, or debugging container-died errors.
- Presence on PATH is what the build verifies; it does not guarantee a listed tool succeeds for every invocation.
