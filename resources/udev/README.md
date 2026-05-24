# resources/udev/

Host-side udev rules for Tang Nano 4K USB device access.

## Why host-side only

udev runs on the host OS, not inside the container. Rules installed inside the container have no effect on device node creation or permissions. The rules file is shipped in this repo so users can install it on their host. `Dockerfile.gowin` COPYs it into the image at `/usr/local/share/claude-env/99-tangnano.rules` as a reference copy only — this does not activate the rules.

## VID:PID coverage

Two VID:PID pairs are covered:

- `28e9:0189` (Sipeed/BL702): primary VID for Tang Nano 4K default firmware. The BL702 bridge chip uses Sipeed's vendor ID; this is the common case.
- `0403:6010` (FTDI VID): present on some board revisions. Existence is based on code comments and field reports, not confirmed on every hardware revision. Including the rule is harmless if the VID does not match.

Both use `MODE=0660 GROUP=plugdev`. `MODE=0666` was rejected (world-writable USB access violates least-privilege). `plugdev` GID 46 matches between Ubuntu hosts and the container; non-Ubuntu hosts with a different GID must use `--privileged` as a workaround.

## Invariants

- The BL702 chip with Sipeed VID `0x28e9` does NOT trigger `ftdi_sio` autobind. The FTDI VID variant `0x0403` does. The rules file addresses both but the `ftdi_sio` conflict is only relevant for the FTDI VID case.
- `codeuser` is added to `dialout` and `plugdev` groups in `Dockerfile.gowin`. The udev rules grant group access to `plugdev`; `dialout` covers serial device ownership.
- Serial device nodes (`/dev/ttyUSB*`, `/dev/ttyACM*`) are static at container start. The `--device` flags in `launch.sh` bind the nodes that exist when `launch.sh` runs. Connect the board before launching the container; hot-plug for serial nodes is not supported without `--privileged`.
