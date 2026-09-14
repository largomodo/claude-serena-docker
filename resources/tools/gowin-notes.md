# gowin notes

Condensed from README.md Troubleshooting > gowin; edit both.

OSS flow command chain: `yosys` (`synth_gowin`) -> `nextpnr-himbaechel-gowin`/`nextpnr-gowin`
with the GW1NSR-4C device string -> `gowin_pack` -> `openFPGALoader --cable
tangnano4k --board tangnano4k bitstream.fs`.

Gowin EDA flow: encrypted IP (pragma protect) only synthesizes through
`gw_sh` Tcl scripts. The Education edition (default) needs no license
server; the Standard edition needs Sipeed's server at
`gowinlic.sipeed.com:10559`.

GW1NSR primitives (`PLLVR`, `OSER10`, `TLVDS_OBUF`) may fail in the OSS
flow -- verify against Gowin EDA if synthesis or PnR reports unknown
primitives.

USB access: Sipeed VID:PID `28e9:0189` (primary) vs FTDI `0403:6010` (some
board revisions). Host udev rules live at
/usr/local/share/claude-env/99-tangnano.rules. FTDI-VID boards may need
`sudo rmmod ftdi_sio` on the host to release the device from the kernel's
`ftdi_sio` driver. Devices must be connected before `launch.sh` runs.

The bundled Programmer at /opt/gowin-eda/Programmer/bin is available but
untested headless; `openFPGALoader` is the recommended flashing tool.

This file is prose only: check-tools.sh verifies the sheet's `## Tools` and `## Environment` tables, never the content here.
