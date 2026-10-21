# claude-env container toolchain: c-pico

## Tools (c-pico)

| Tool | What | Use when |
| --- | --- | --- |
| `cmake` | Build system generator | Configuring or building a Pico SDK project |
| `arm-none-eabi-gcc` | ARM Cortex-M toolchain | Building for the RP2040/RP2350 ARM cores |
| `riscv32-pico-elf-gcc` | RISC-V toolchain at /opt/riscv-toolchain | Building for the RP2350 Hazard3 RISC-V cores |
| `picotool` | Pico device inspection/flashing | Flashing or inspecting a Pico board over USB |
| `openocd` | Raspberry Pi fork; CMSIS-DAP/picoprobe support | Debugging over SWD/JTAG |
| `gdb-multiarch` | Multi-architecture debugger | Debugging ARM or RISC-V firmware |
| `minicom` | Serial terminal | Reading UART output from a connected board |
| `clangd` | apt clangd; Serena's C/C++ LS via ls_path | Checking a translation unit outside Serena (`clangd --check`) |

## Environment (c-pico)

| Variable | What |
| --- | --- |
| `VARIANT` | Container variant name (`c-pico`) |
| `PICO_SDK_PATH` | Pico SDK root |
| `PICO_RISCV_TOOLCHAIN_PATH` | RISC-V toolchain root |

## Notes (c-pico)

- `PICO_TOOLCHAIN_PATH` is intentionally unset; setting it breaks ARM builds.
- Serial devices appear as /dev/ttyACM* only if connected before launch.
- The RISC-V compiler is `riscv32-pico-elf-gcc` (not `riscv32-unknown-elf-gcc`); `PICO_RISCV_TOOLCHAIN_PATH` points at the toolchain root and the Pico SDK finds the compiler by its `riscv32-pico-elf` prefix.
- Presence on PATH is what the build verifies; it does not guarantee a listed tool succeeds for every invocation.
