# claude-env container toolchain: java

This section describes the java variant's toolchain, in addition to the
base toolchain in claude-env.md above.

## Tools (java)

| Tool | What | Use when |
| --- | --- | --- |
| `java` `javac` `jar` | Temurin JDK 21 at /opt/java/openjdk | Compiling, running, or packaging Java code |
| `mvn` | Maven; `~/.m2` persisted across launches | Building or resolving dependencies for a Maven project |

## Environment (java)

| Variable | What |
| --- | --- |
| `VARIANT` | Container variant name (`java`) |
| `JAVA_HOME` | JDK installation root |

## Notes (java)

- Serena runs JDT-LS from /opt/jdtls in upstream mode (2G heap, Lombok at /opt/lombok/lombok.jar).
- Serena runs JDT-LS with a cold start that can exceed its 10s timeout on first index; rerun `serena project index` if it warns.
- No Gradle is baked into the image; use the project's own `gradlew`.
- Presence on PATH is what the build verifies; it does not guarantee a listed tool succeeds for every invocation.
