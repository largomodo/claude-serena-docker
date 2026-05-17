// SetSnesRegisters.java
// Register name note: the 65816 .slaspec defines context register bitfields as
// ctx_MF, ctx_XF, ctx_EF (not MF, XF, EF). Using the wrong names causes a
// silent no-op at runtime with no error logged.
// Sets 65816 processor mode flags and registers at the ROM entry point.
// Intended for use as a -postScript in headless mode.
//
// Default values assume native mode, 16-bit accumulator, 16-bit index.
// Override via script arguments:
//   arg0 = MF  (0 or 1, memory/accumulator width flag)
//   arg1 = XF  (0 or 1, index register width flag)
//   arg2 = EF  (0 or 1, emulation flag; 0 = native, 1 = emulation)
//
// @category SNES

import ghidra.app.script.GhidraScript;
import ghidra.program.model.lang.Register;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Program;
import java.math.BigInteger;

public class SetSnesRegisters extends GhidraScript {

    @Override
    protected void run() throws Exception {
        Program program = currentProgram;
        if (program == null) {
            printerr("No program loaded.");
            return;
        }

        // Parse arguments or use defaults (native mode, 16-bit A, 16-bit XY)
        int mf = 0;  // 0 = 16-bit accumulator
        int xf = 0;  // 0 = 16-bit index
        int ef = 0;  // 0 = native mode

        String[] args = getScriptArgs();
        if (args.length >= 1) mf = Integer.parseInt(args[0]);
        if (args.length >= 2) xf = Integer.parseInt(args[1]);
        if (args.length >= 3) ef = Integer.parseInt(args[2]);

        Address entryPoint = program.getMinAddress();
        if (entryPoint == null) {
            printerr("Cannot determine entry point.");
            return;
        }

        println("Setting 65816 registers at " + entryPoint);
        println("  ctx_MF=" + mf + " ctx_XF=" + xf + " ctx_EF=" + ef);

        setRegisterValue(program, entryPoint, "ctx_MF", mf);
        setRegisterValue(program, entryPoint, "ctx_XF", xf);
        setRegisterValue(program, entryPoint, "ctx_EF", ef);

        // DBR and PBR default to 0 for most SNES ROMs at reset
        setRegisterValue(program, entryPoint, "DBR", 0x00);
        setRegisterValue(program, entryPoint, "PBR", 0x00);
        setRegisterValue(program, entryPoint, "DP",  0x0000);
        setRegisterValue(program, entryPoint, "SP",  0x01FF);

        println("Register setup complete.");
    }

    private void setRegisterValue(Program program, Address addr,
                                  String regName, long value)
                                  throws Exception {
        Register reg = program.getLanguage().getRegister(regName);
        if (reg == null) {
            printerr("Register not found: " + regName
                     + " -- check 65816 processor module installation.");
            return;
        }
        program.getProgramContext().setValue(
            reg, addr, addr, BigInteger.valueOf(value));
        println("  Set " + regName + " = " + value);
    }
}
