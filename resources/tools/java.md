# claude-env container toolchain: java

This section describes the java variant's toolchain, in addition to the
base toolchain in claude-env.md above.

## Tools (java)

| Tool | What | Use when |
| --- | --- | --- |
| `java` `javac` `jar` | Temurin JDK 25 at /opt/java/openjdk | Compiling, running, or packaging Java code |
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
- apt Maven on JDK 25 prints `sun.misc.Unsafe` deprecation WARNING lines from its bundled guava; they are cosmetic and do not indicate a build failure.
- JDT-LS needs a Java 21 or newer runtime and runs on this JDK 25.
- Lombok 1.18.48 supports JDK 25, so annotation processing works under the image JDK.
- Presence on PATH is what the build verifies; it does not guarantee a listed tool succeeds for every invocation.
