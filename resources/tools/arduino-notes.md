# arduino notes

Condensed from README.md Troubleshooting > arduino; edit both.

Compile and upload: `arduino-cli compile -b arduino:avr:nano <sketch>` then
`arduino-cli upload -p /dev/ttyUSB0 -b arduino:avr:nano <sketch>`. On
`avrdude: stk500_recv(): programmer is not responding`, switch both commands
to `arduino:avr:nano:cpu=atmega328old` -- most clones carry the old
ATmegaBOOT bootloader and nothing in the image can detect which bootloader a
board has.

Board discovery and serial: `arduino-cli board list`, `arduino-cli monitor -p
/dev/ttyUSB0 -c baudrate=9600`, or `minicom -D /dev/ttyUSB0 -b 9600`. A
genuine Nano enumerates as FTDI FT232RL, clones as CH340, both under
/dev/ttyUSB*. Device nodes are bound at container start, so connect the
board before `./launch.sh`. On Ubuntu hosts, `brltty` can claim a CH340
device (1a86:7523) -- check `dmesg` on the host.
Non-Ubuntu hosts whose dialout GID differs from 20 need `--privileged`, the same caveat gowin documents for `plugdev`.

Libraries: `arduino-cli lib search <name>` / `arduino-cli lib install
"<name>"` land under `~/Arduino/libraries`, which `launch.sh` persists to
`.claudeproject/Arduino`.

Serena and `.ino`: clangd has no `.ino` language, so an `.ino`-only sketch
reports no source files. Run `arduino-cli compile -b arduino:avr:nano
--only-compilation-database --build-path build <sketch>` and symlink
`build/compile_commands.json` next to the sources; keep a thin `.ino` and
put logic in `.cpp`/`.h` files so clangd indexes it.

clangd, not init-workspace.sh, consumes the resulting compile_commands.json --
init-workspace.sh's clangd arm only glob-matches `.cpp`/`.h`/`.c` files for
Serena's language detection.

simavr: `simavr -m atmega328p -f 16000000 build/<sketch>.ino.elf` runs the
ELF headlessly (Ctrl-C to stop). `-g` opens a gdb stub on :1234, but
`avr-gdb` is not shipped in this image, so the stub goes unused.

Two toolchains: apt `avr-gcc`/`avrdude` on PATH serve bare-metal work and
ELF inspection (`avr-size`, `avr-objdump -d`); arduino-cli always uses the
core's bundled avr-gcc/avrdude under
`/opt/arduino15/packages/arduino/tools/`. Standalone flash of a .hex:
`avrdude -c arduino -p m328p -P /dev/ttyUSB0 -b 115200 -U flash:w:<file>.hex`
(`-b 57600` for the old bootloader).

This file is prose only: check-tools.sh verifies the sheet's `## Tools` and `## Environment` tables, never the content here.
