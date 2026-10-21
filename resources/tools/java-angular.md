# claude-env container toolchain: java-angular

Same Tools rows as the java variant, plus a variant-local Node and the
Angular CLI.

## Tools (java-angular)

| Tool | What | Use when |
| --- | --- | --- |
| `java` `javac` `jar` | Temurin JDK 25 at /opt/java/openjdk | Compiling, running, or packaging Java code |
| `mvn` | Maven; `~/.m2` persisted across launches | Building or resolving dependencies for a Maven project |
| `node` `npm` `npx` | Node 24 at /opt/node, shadows the base image's apt Node | Running the Angular dev server, npm scripts |
| `ng` | Global Angular CLI pinned to a major; delegates to the project-local CLI inside a project | Scaffolding or running Angular commands |

## Environment (java-angular)

| Variable | What |
| --- | --- |
| `VARIANT` | Container variant name (`java-angular`) |
| `JAVA_HOME` | JDK installation root |

## Notes (java-angular)

- Serena runs JDT-LS from /opt/jdtls (upstream mode, 2G heap, Lombok in /opt/lombok).
- `ng serve --host 0.0.0.0` is required to reach port 4200 from the host.
- apt Maven on JDK 25 prints `sun.misc.Unsafe` deprecation WARNING lines from its bundled guava; they are cosmetic and do not indicate a build failure.
- JDT-LS needs a Java 21 or newer runtime and runs on this JDK 25.
- Lombok 1.18.48 supports JDK 25, so annotation processing works under the image JDK.
- Global installs must use `sudo /opt/node/bin/npm install -g <pkg>`; a bare `sudo npm install -g` resolves the apt npm instead.
- Angular LS in Serena stays degraded until `npm ci` has run in the project.
- Read /usr/local/share/claude-env/tools/java-angular-notes.md when setting up the dev server, proxying /api, choosing a test runner, or scaffolding another Angular major.
- Presence on PATH is what the build verifies; it does not guarantee a listed tool succeeds for every invocation.
