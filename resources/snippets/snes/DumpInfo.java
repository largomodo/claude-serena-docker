// @category SNES
import ghidra.app.script.GhidraScript;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.address.Address;
import ghidra.program.model.symbol.Symbol;
public class DumpInfo extends GhidraScript {
    @Override protected void run() throws Exception {
        println("=== LANGUAGE: " + currentProgram.getLanguageID());
        println("=== IMAGE BASE: " + currentProgram.getImageBase());
        println("=== MEMORY BLOCKS ===");
        for (MemoryBlock b : currentProgram.getMemory().getBlocks()) {
            println(String.format("%-16s %s - %s  %6dB  %s%s%s%s",
                b.getName(), b.getStart(), b.getEnd(), b.getSize(),
                b.isRead()?"r":"-", b.isWrite()?"w":"-", b.isExecute()?"x":"-",
                b.isInitialized()?" init":""));
        }
        println("=== ENTRY POINTS ===");
        for (Address a : currentProgram.getSymbolTable().getExternalEntryPointIterator()) {
            println("entry: " + a);
        }
        println("=== FUNCTIONS: " + currentProgram.getFunctionManager().getFunctionCount());
        long insns = currentProgram.getListing().getNumInstructions();
        println("=== INSTRUCTIONS: " + insns);
    }
}
