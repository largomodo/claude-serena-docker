# claude-env container toolchain: arduino

## Tools (arduino)

| Tool | What | Use when |
| --- | --- | --- |
| `arduino-cli` | Arduino CLI with the `arduino:avr` core preinstalled | Compiling, uploading, monitoring, or installing libraries for a Nano sketch |
| `avr-gcc` `avr-objdump` `avr-size` | apt AVR toolchain (arduino-cli uses its own bundled avr-gcc) | Bare-metal AVR C, inspecting the ELF arduino-cli produces |
| `avrdude` | Standalone flasher | Writing a .hex without arduino-cli |
| `simavr` | AVR simulator | Running an ATmega328P ELF without hardware |
| `minicom` | Serial terminal | Reading the Nano's UART output |

## Environment (arduino)

| Variable | What |
| --- | --- |
| `VARIANT` | Container variant name (`arduino`) |
| `ARDUINO_DIRECTORIES_DATA` | arduino-cli data dir with the preinstalled core |
| `ARDUINO_DIRECTORIES_USER` | Sketchbook and installed libraries; persisted by launch.sh |

## Notes (arduino)

- FQBN `arduino:avr:nano` (Optiboot); retry with `arduino:avr:nano:cpu=atmega328old` on `avrdude: stk500_recv(): programmer is not responding`.
- Board appears as /dev/ttyUSB* (FTDI/CH340) or /dev/ttyACM* if connected before launch.sh.
- Read /usr/local/share/claude-env/tools/arduino-notes.md for the compile-database, upload, and simavr recipes; `.ino` files are not indexed by Serena.
- Presence on PATH is what the build verifies; it does not guarantee a listed tool succeeds for every invocation.
