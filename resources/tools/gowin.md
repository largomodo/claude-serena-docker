# claude-env container toolchain: gowin

## Tools (gowin)

| Tool | What | Use when |
| --- | --- | --- |
| `yosys` | HDL synthesis | Synthesizing Verilog for the OSS flow |
| `nextpnr-himbaechel-gowin` | Place and route | Placing and routing a synthesized design |
| `gowin_pack` `gowin_unpack` | Apicula bitstream packer/unpacker | Producing or inspecting a .fs bitstream |
| `openFPGALoader` | Primary flashing tool (`--cable tangnano4k`) | Flashing the Tang Nano 4K |
| `iverilog` `verilator` `ghdl` | Simulation | Simulating a Verilog or VHDL design |
| `gw_sh` | Gowin EDA Tcl shell (/opt/gowin-eda/IDE/bin) | Synthesizing encrypted IP (pragma protect) |

## Environment (gowin)

| Variable | What |
| --- | --- |
| `VARIANT` | Container variant name (`gowin`) |
| `QT_QPA_PLATFORM` | Forces offscreen Qt rendering |
| `LD_PRELOAD` | Preloads system libfreetype over Gowin's bundled copy |

## Notes (gowin)

- No Verilog LSP; Serena indexes Python only.
- pragma-protect IP cores only synthesize with `gw_sh`.
- Read /usr/local/share/claude-env/tools/gowin-notes.md when choosing OSS vs Gowin flow, flashing, or debugging USB/JTAG access.
- Presence on PATH is what the build verifies; it does not guarantee a tool succeeds for every invocation.
