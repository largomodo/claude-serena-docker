# Ghidra Headless SNES Environment — Setup Guide

> **Audience:** Developer responsible for maintaining the Docker image that provides the SNES analysis environment.
> Architecture decisions: DL-001 (Ghidra 12.0.4 required for ViewtifulSlayer 12.x API),
> DL-003 (ViewtifulSlayer forks used; achan1989 originals are archived),
> DL-009 (Sleigh spec pre-compiled at build time: headless mode does NOT auto-compile .slaspec files; GUI does, headless does not).
> The developer who *uses* this environment is a different person; see the companion Usage Guide.
> In the containerized setup, all steps below are performed automatically by the Dockerfile at build time.

---

## Overview

The SNES disassembly environment is baked into the Docker image at build time. There is no manual provisioning required at runtime. This guide documents the build steps and the reasoning behind them, so that maintainers understand what the Dockerfile does and can troubleshoot or upgrade the toolchain.

To rebuild the image after any changes:

```bash
./build.sh [optional_tag]
```

---

## 1. Base Requirements (Handled by Dockerfile)

| Component | Version | Container Path |
|-----------|---------|----------------|
| JDK | 21 (Temurin) | `/opt/java/openjdk/` (`$JAVA_HOME`) |
| Ghidra | 12.0.4 | `/opt/ghidra/` |
| Git | Any recent | System package |
| Gradle | Via wrapper in repo | Downloaded on first build |
| unzip | Any | System package |

The Dockerfile ARGs `GHIDRA_VERSION=12.0.4` and `GHIDRA_DATE=20260303` control the Ghidra download URL. To pin to a different version, override these ARGs in `build.sh`.

Ghidra 12.0.4 SHA-256:
```
c3b458661d69e26e203d739c0c82d143cc8a4a29d9e571f099c2cf4bda62a120
```

---

## 2. Ghidra Installation (Handled by Dockerfile)

The Dockerfile downloads and extracts Ghidra to `/opt/ghidra/` and symlinks `analyzeHeadless` to `/usr/local/bin/`:

```bash
mkdir -p /opt/ghidra
wget -q -O ghidra.zip "${GHIDRA_URL}"
unzip -q ghidra.zip -d /opt/ghidra_tmp
mv /opt/ghidra_tmp/ghidra_${GHIDRA_VERSION}_PUBLIC/* /opt/ghidra/
rm -rf /opt/ghidra_tmp ghidra.zip
ln -s /opt/ghidra/support/analyzeHeadless /usr/local/bin/analyzeHeadless
```

---

## 3. SNES Loader Extension (Handled by Dockerfile)

### 3.1 Build

The Dockerfile clones [ViewtifulSlayer/ghidra-snes-loader](https://github.com/ViewtifulSlayer/ghidra-snes-loader) and builds the extension against the installed Ghidra:

```bash
git clone --depth 1 https://github.com/ViewtifulSlayer/ghidra-snes-loader.git /tmp/ghidra-snes-loader
cd /tmp/ghidra-snes-loader/SnesLoader
GHIDRA_INSTALL_DIR=/opt/ghidra ./gradlew buildExtension
```

This produces a ZIP in `dist/`, e.g.:
```
dist/ghidra_12.0.4_PUBLIC_YYYYMMDD_SnesLoader.zip
```

### 3.2 Install into Ghidra Extensions

Extensions used in headless mode must be **extracted** into `Ghidra/Extensions/`, not copied as a ZIP. The Dockerfile:

```bash
mkdir -p /opt/ghidra/Ghidra/Extensions/SnesLoader
unzip -q dist/ghidra_*_SnesLoader.zip -d /opt/ghidra/Ghidra/Extensions/SnesLoader
```

**Nested-directory bug prevention:** Some versions of the ZIP produce a nested `SnesLoader/SnesLoader/` layout. The Dockerfile detects and flattens this:

```bash
if [ ! -f /opt/ghidra/Ghidra/Extensions/SnesLoader/extension.properties ]; then
    NESTED=$(find /opt/ghidra/Ghidra/Extensions/SnesLoader -name extension.properties | head -1)
    if [ -z "$NESTED" ]; then echo "ERROR: extension.properties not found"; exit 1; fi
    NESTED_DIR=$(dirname "$NESTED")
    mv "$NESTED_DIR"/* /opt/ghidra/Ghidra/Extensions/SnesLoader/
    rm -rf "$NESTED_DIR"
fi
```

After installation, `extension.properties` must be directly under `SnesLoader/` (not nested). Ghidra discovers extensions by scanning for this file; a wrong depth causes the extension to be silently ignored.

### 3.3 Loader name

The loader's `getName()` method returns `SNES ROM`. This is the string used in the `-loader` flag for `analyzeHeadless`.

---

## 4. 65816 Processor Module (Handled by Dockerfile)

### 4.1 Clone and copy

The Dockerfile clones [ViewtifulSlayer/ghidra-65816](https://github.com/ViewtifulSlayer/ghidra-65816) (branch `master`) and copies it into the Ghidra Processors directory:

```bash
git clone --depth 1 https://github.com/ViewtifulSlayer/ghidra-65816.git /tmp/ghidra-65816
cp -r /tmp/ghidra-65816 /opt/ghidra/Ghidra/Processors/65816
```

This is a raw Sleigh-based processor module; it has no Gradle build step.

### 4.2 Language and compiler spec IDs

From `65816.ldefs`:
- Language ID: `65816:LE:16:default`
- Compiler spec ID: `default`

These are the values passed to `-processor` and `-cspec` in every `analyzeHeadless` invocation.

---

## 5. Sleigh Spec Pre-compilation (Handled by Dockerfile)

Ghidra's GUI auto-compiles `.slaspec` files on first use; headless mode does not. The Dockerfile compiles the spec at build time:

```bash
/opt/ghidra/support/sleigh /opt/ghidra/Ghidra/Processors/65816/data/languages/65816.slaspec
```

This produces `65816.sla` in the same directory. Without this file, headless analysis will fail with a `SleighException`.

The ViewtifulSlayer fork includes qwertymodo's fix for unused Sleigh labels that caused compilation failures in earlier forks.

---

## 6. GhidraScripts Directory (Handled by Dockerfile)

The Dockerfile creates `/opt/ghidra/Ghidra/Scripts/` and copies `SetSnesRegisters.java` into it:

```bash
mkdir -p /opt/ghidra/Ghidra/Scripts
COPY resources/scripts/SetSnesRegisters.java /opt/ghidra/Ghidra/Scripts/SetSnesRegisters.java
```

The `GHIDRA_SCRIPTS_DIR` environment variable is set to `/opt/ghidra/Ghidra/Scripts` and is consumed by the `snes-analyze` wrapper.

**Register names:** The script uses `ctx_MF`, `ctx_XF`, `ctx_EF` (context register bitfields defined in the 65816 `.slaspec`). These differ from the names documented in some older references (`MF`, `XF`, `EF`); using the wrong names causes a silent no-op at runtime.

---

## 7. Build Artifact Cleanup (Handled by Dockerfile)

The Dockerfile cleans up within the same `RUN` layer to prevent artifacts from persisting in intermediate Docker layers:

```bash
rm -rf /tmp/ghidra-snes-loader /tmp/ghidra-65816 /root/.gradle \
       /opt/ghidra/Ghidra/Processors/65816/.git
```

The Gradle cache (`/root/.gradle`) can be several hundred MB and must be removed.

---

## 8. Validating the Built Image

After building, verify the SNES toolchain artifacts are present:

```bash
# Verify Sleigh pre-compilation
docker run --rm <image> test -f /opt/ghidra/Ghidra/Processors/65816/data/languages/65816.sla

# Verify loader extension installed at correct depth
docker run --rm <image> test -f /opt/ghidra/Ghidra/Extensions/SnesLoader/extension.properties

# Verify SetSnesRegisters.java uses correct register names
docker run --rm <image> grep -q 'ctx_MF' /opt/ghidra/Ghidra/Scripts/SetSnesRegisters.java

# Verify x86 processor survives Ghidra upgrade (non-regression)
docker run --rm <image> ls /opt/ghidra/Ghidra/Processors/x86/data/languages/

# Verify Gradle cache was cleaned
docker run --rm <image> test ! -d /root/.gradle

# Verify analyzeHeadless is functional
docker run --rm <image> analyzeHeadless --help
```

The HEALTHCHECK in the Dockerfile also verifies the presence of `65816.sla` and `extension.properties`.

---

## 9. Environment Variables

The Dockerfile sets:

| Variable | Value | Purpose |
|----------|-------|---------|
| `GHIDRA_SCRIPTS_DIR` | `/opt/ghidra/Ghidra/Scripts` | Script path for `analyzeHeadless -scriptPath` |
| `GHIDRA_PROJECTS_DIR` | `/workspace/.ghidra-projects` | Project directory for `analyzeHeadless` (persisted to host) |

`GHIDRA_PROJECTS_DIR` points into `/workspace`, which is bind-mounted from the host. Ghidra project files are written here and survive container restarts. The `.ghidra-projects/` directory is gitignored.

---

## 10. Maintenance Notes

- **Ghidra upgrades:** Update `GHIDRA_VERSION` and `GHIDRA_DATE` ARGs in the Dockerfile. The loader and processor will be rebuilt against the new version automatically. If the major version changes, verify that the ViewtifulSlayer forks are compatible (they target Ghidra 12.x API). Verify SHA-256 of the new release.
- **Extension version mismatch:** The `extension.properties` file embeds the Ghidra version the extension was built against. A mismatch with the running Ghidra version causes the extension to be silently ignored (no error logged). This is prevented by building the extension against the same Ghidra version that is installed.
- **Sleigh recompilation:** If the `.slaspec` or any `.sinc` file in the processor module changes, the `sleigh` command must be re-run. This happens automatically when the Dockerfile is rebuilt from the clone step.
- **Fallback to 12.0.3:** If 12.0.4 causes build failures with the loader, pin to `GHIDRA_VERSION=12.0.3` and `GHIDRA_DATE=20260220` (verified working with the loader). This is a two-ARG change in the Dockerfile.
