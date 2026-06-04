// SeedSnesVectors.java
// Seeds disassembly from the SNES/65816 hardware vector table so that
// Ghidra's auto-analysis has real entry points to propagate from.
//
// The 65816 vector table lives in bank $00 near the top of the address
// space. Each vector is a little-endian 16-bit pointer into bank $00.
//
//   Native-mode vectors (E=0):       Emulation-mode vectors (E=1):
//     $00FFE4  COP                      $00FFF4  COP
//     $00FFE6  BRK                      $00FFF6  (unused / BRK shares IRQ)
//     $00FFE8  ABORT                    $00FFF8  ABORT
//     $00FFEA  NMI                      $00FFFA  NMI
//     $00FFEC  (reserved)               $00FFFC  RESET   <-- always entered in E=1
//     $00FFEE  IRQ                      $00FFFE  IRQ/BRK
//
// At hardware reset the CPU is forced into emulation mode (E=1, 8-bit A/X/Y),
// so RESET is always seeded with EF=1, MF=1, XF=1. The native handlers run in
// whatever state the game was in when the interrupt fired -- unknowable
// statically -- so we seed them native (EF=0) with a configurable, conservative
// default width. Override per-run; any REP/SEP inside the handler corrects the
// width as disassembly flows forward.
//
// Register-name note: the 65816 .slaspec names the context bitfields
// ctx_MF, ctx_XF, ctx_EF (NOT MF/XF/EF). Wrong names = silent no-op.
//
// Arguments (all optional):
//   arg0 = native MF (0=16-bit acc, 1=8-bit acc)   default 1
//   arg1 = native XF (0=16-bit idx, 1=8-bit idx)   default 1
//   arg2 = seed emulation vectors too (0/1)         default 0
//
// @category SNES

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.MemoryBlock;
import java.math.BigInteger;

public class SeedSnesVectors extends GhidraScript {

    // A vector table entry: name, address of the pointer, and whether the
    // target runs in emulation mode.
    private static class Vec {
        final String name; final long ptr; final boolean emulation;
        Vec(String name, long ptr, boolean emulation) {
            this.name = name; this.ptr = ptr; this.emulation = emulation;
        }
    }

    private int nativeMF = 1;   // conservative default: 8-bit accumulator
    private int nativeXF = 1;   // conservative default: 8-bit index
    private boolean doEmu = false;

    @Override
    protected void run() throws Exception {
        if (currentProgram == null) { printerr("No program loaded."); return; }

        String[] a = getScriptArgs();
        if (a.length >= 1) nativeMF = Integer.parseInt(a[0]);
        if (a.length >= 2) nativeXF = Integer.parseInt(a[1]);
        if (a.length >= 3) doEmu    = Integer.parseInt(a[2]) != 0;

        Vec[] vectors = new Vec[] {
            // Native (E=0)
            new Vec("COP_native",   0x00FFE4L, false),
            new Vec("BRK_native",   0x00FFE6L, false),
            new Vec("ABORT_native", 0x00FFE8L, false),
            new Vec("NMI_native",   0x00FFEAL, false),
            new Vec("IRQ_native",   0x00FFEEL, false),
            // Emulation (E=1)
            new Vec("COP_emu",      0x00FFF4L, true),
            new Vec("ABORT_emu",    0x00FFF8L, true),
            new Vec("NMI_emu",      0x00FFFAL, true),
            new Vec("RESET",        0x00FFFCL, true),  // always seeded
            new Vec("IRQ_BRK_emu",  0x00FFFEL, true),
        };

        println("=== Seeding SNES vectors (native MF=" + nativeMF
                + " XF=" + nativeXF + ", emulation handlers="
                + (doEmu ? "yes" : "RESET only") + ") ===");

        int seeded = 0;
        for (Vec v : vectors) {
            boolean isReset = v.name.equals("RESET");
            if (v.emulation && !isReset && !doEmu) continue;

            Address ptrAddr = toAddr(v.ptr);
            if (!isReadable(ptrAddr) || !isReadable(ptrAddr.add(1))) {
                println(String.format("  %-12s @%s  (pointer not in memory, skipped)",
                        v.name, ptrAddr));
                continue;
            }
            int lo = getByte(ptrAddr) & 0xFF;
            int hi = getByte(ptrAddr.add(1)) & 0xFF;
            int target16 = (hi << 8) | lo;

            if (target16 == 0x0000 || target16 == 0xFFFF) {
                println(String.format("  %-12s @%s -> $%04X  (unused, skipped)",
                        v.name, ptrAddr, target16));
                continue;
            }

            // A pointer into the vector region itself (e.g. $FFE8) is never a
            // real handler -- it means that interrupt is unused on this ROM.
            if (target16 >= 0xFFE0) {
                println(String.format("  %-12s @%s -> $%04X  (points into vector table, skipped)",
                        v.name, ptrAddr, target16));
                continue;
            }

            // Vector targets are bank $00 (PBR=0 at reset / for these handlers).
            Address target = toAddr(target16 & 0xFFFF);
            MemoryBlock blk = getMemoryBlock(target);
            if (blk == null || !blk.isInitialized()) {
                println(String.format("  %-12s @%s -> $%06X  (target not in initialized ROM, skipped)",
                        v.name, ptrAddr, target.getOffset()));
                continue;
            }

            int ef = v.emulation ? 1 : 0;
            // Emulation mode forces 8-bit A/X/Y; native uses the chosen defaults.
            int mf = v.emulation ? 1 : nativeMF;
            int xf = v.emulation ? 1 : nativeXF;

            setCtx(target, "ctx_EF", ef);
            setCtx(target, "ctx_MF", mf);
            setCtx(target, "ctx_XF", xf);
            // Reasonable reset-time register defaults for address resolution.
            setCtx(target, "DBR", 0x00);
            setCtx(target, "PBR", 0x00);
            setCtx(target, "DP",  0x0000);
            setCtx(target, "SP",  0x01FF);

            disassemble(target);
            Function f = getFunctionAt(target);
            if (f == null) {
                f = createFunction(target, v.name);
            } else {
                f.setName(v.name, ghidra.program.model.symbol.SourceType.USER_DEFINED);
            }
            addEntryPoint(target);

            boolean ok = getInstructionAt(target) != null;
            println(String.format("  %-12s @%s -> $%06X  EF=%d MF=%d XF=%d  %s",
                    v.name, ptrAddr, target.getOffset(), ef, mf, xf,
                    ok ? "[disassembled]" : "[FAILED to decode]"));
            if (ok) seeded++;
        }

        println("=== Seeded " + seeded + " vector handler(s); "
                + "auto-analysis will propagate from here ===");
    }

    private boolean isReadable(Address addr) {
        MemoryBlock b = getMemoryBlock(addr);
        return b != null && b.isInitialized();
    }

    private void setCtx(Address addr, String regName, long value) {
        try {
            Register reg = currentProgram.getLanguage().getRegister(regName);
            if (reg == null) {
                printerr("  Register not found: " + regName
                         + " -- check 65816 module install.");
                return;
            }
            currentProgram.getProgramContext().setValue(
                reg, addr, addr, BigInteger.valueOf(value));
        } catch (Exception e) {
            printerr("  Failed setting " + regName + ": " + e.getMessage());
        }
    }
}
