# Android notes (android)

The host adb server, Frida, mitmproxy, blutter and Unity sections mirror the
`android:` Troubleshooting subsections in README.md; edit both. The React
Native and REA tool sections are usage notes with no README counterpart.

**Host adb server.** The container has no devices and no privileges; adb and
Frida reach devices through the host's adb server. init-workspace.sh starts a
socat relay 127.0.0.1:5037 -> `$ADB_HOST_SERVER` (default
host.docker.internal:5037; override with `ADB_HOST_SERVER` in the host shell
or .env, which launch.sh forwards). The relay exists because Frida's adb
client ignores `ADB_SERVER_SOCKET` and dials 127.0.0.1:5037, so setting that
variable alone would leave Frida without a device path. On the host:

```bash
adb kill-server
adb -L tcp:<docker0-ip>:5037 server nodaemon &   # docker0 IP: ip -4 addr show docker0 (usually 172.17.0.1)
```

`adb -a` also works but binds every host interface and needs a firewall
rule. A server bound to docker0 is reachable, unauthenticated, from every
container on the default bridge and from local processes: start it only for
dynamic sessions and run `adb kill-server` afterwards. Optional hardening: a
host firewall rule limiting tcp/5037 on docker0. Relay log:
.claudeproject/adb-relay.log.

If the host server is not running or not bound to the docker0 IP, socat
still accepts on 127.0.0.1:5037 and closes after its upstream connect fails,
so `adb devices` shows a connection/protocol error instead of "daemon not
running". Check that `ss -ltn | grep 5037` on the host shows
<docker0-ip>:5037, `echo $ADB_HOST_SERVER` and
`getent hosts host.docker.internal` in the container, and the connect errors
in .claudeproject/adb-relay.log.

socat dials the host server per connection, so the relay starts cleanly even
when the host server is down.

**Frida.** Push /opt/frida-server/frida-server-17.23.2-android-{arm64,x86_64}
to /data/local/tmp on a rooted device or emulator, `chmod 755`, run as root.
frida-server, pip frida and REA's npm frida are all 17.23.2. Then
`frida-ps -U` or REA's Frida tools.

**mitmproxy.** `adb reverse tcp:8080 tcp:8080`, then
`mitmdump -p 8080 -w flows.mitm`, device proxy 127.0.0.1:8080. launch.sh
publishes 8080 on host 127.0.0.1 only, so a device Wi-Fi proxy pointing at
the host's LAN IP does not work; use adb reverse. Apps targeting API 24+
ignore user CA certificates unless the device is rooted or the app is
patched (network_security_config). REA's capture tools read the flows via
REA_MITMDUMP_COMMAND.

**blutter (Flutter).** `blutter <apk or lib/arm64-v8a dir> <outdir>`. The
first run per Dart version clones the Dart SDK from GitHub and builds it for
minutes (network needed); the cache lives in .claudeproject/blutter.

**Unity.** `cpp2il --game-path <dir>`;
`il2cppdumper <libil2cpp.so> <global-metadata.dat> <outdir>`. Il2CppDumper is a
net7 build; Ubuntu 26.04 apt ships only .NET 10, so the wrapper sets
`DOTNET_ROLL_FORWARD=Major` to start it. Its config.json has
`RequireAnyKey=false`; with true it waits for a keypress on stdin, which blocks
a headless shell.

**React Native.** `hbc-decompiler index.android.bundle out.js`.

**REA Android tools.** inspect_android_package, search_android_classes,
inspect_android_method, trace_android_references, decode_android_resources,
plus adb and frida tools. The JADX deadline is 120 s by default;
REA_JADX_OPERATION_TIMEOUT_MS and REA_JADX_HEAP_MIB raise it through the
registration env.

**Licensing.** The Android SDK zips fall under the Android SDK License:
images are local builds and are never pushed to a public registry.
