# claude-env container toolchain: android

## Tools (android)

| Tool | What |
| --- | --- |
| `rea` `analyzeHeadless` `r2` | REA CLI; Ghidra 12.1 headless; radare2 for native .so |
| `jadx` `apktool` | DEX decompiler; resource and smali decode/rebuild |
| `adb` `aapt2` `apksigner` `zipalign` `d8` | Android SDK platform and build tools |
| `frida` `frida-ps` `objection` | Frida 17.23.2 clients |
| `mitmdump` | mitmproxy 12.2.3 capture |
| `blutter` `hbc-decompiler` `cpp2il` | Flutter, React Native Hermes, Unity Cpp2IL |

## Environment (android)

| Variable | What |
| --- | --- |
| `VARIANT` | Container variant name (`android`) |
| `JAVA_HOME` `GHIDRA_INSTALL_DIR` `ANDROID_HOME` | JDK, Ghidra, SDK roots |
| `ADB_HOST_SERVER` | Host adb server behind the 127.0.0.1:5037 relay |

## MCP servers (android)

| Server | What |
| --- | --- |
| `rea` | Ghidra, JADX, Apktool, adb, Frida, mitmdump tools |

## Notes (android)

- Binary variant: no Serena project.
- Read /usr/local/share/claude-env/tools/android-notes.md before device, proxy or framework work, rea-notes.md before REA.
- `androguard`, `lief`, `capstone` import from /opt/cli-tools/.venv/bin/python.
- Presence on PATH is what the build verifies, not that a tool succeeds.
