# Initial Instructions: x86 DOS Disassembly Environment

This container is a reverse engineering workbench for 16-bit DOS binaries (.com, .exe). The workspace at `/workspace` contains the binary project to analyze.

---

## Tool Quick Reference

| Tool / Command      | Purpose                                              |
| ------------------- | ---------------------------------------------------- |
| `dis16`             | Linear disassembly (ndisasm, 16-bit real mode)       |
| `r216`              | Interactive/scriptable analysis (radare2, 16-bit)    |
| `dump16`            | AT&T/Intel dump via objdump (i8086, binary mode)     |
| `analyzeHeadless`   | Ghidra headless: automated analysis, export, scripts |
| `python3` (capstone)| Scriptable disassembly framework                     |
| `python3` (pefile)  | MZ/PE header parsing                                 |
| `serena` (MCP)      | Semantic code navigation (for .asm source files)     |

---

## Disassembly Tools

### dis16 (ndisasm)

Linear disassembly from a raw offset. Best for .com files and raw binary blobs.

```bash
# Disassemble entire file
dis16 program.com

# Start at offset 0x100 (useful for .com files that load at CS:0100)
dis16 -o 0x100 program.com

# Disassemble from byte offset 0x20 in the file
dis16 -e 0x20 program.com

# Limit output
dis16 program.com | head -80
```

ndisasm performs linear (non-recursive) disassembly. It does not follow jumps; padding and data bytes will be decoded as instructions.

### r216 (radare2)

Non-interactive batch mode is preferred for LLM use. Pipe commands via `echo` or `-c`.

```bash
# Print entry point disassembly (auto-analyze first)
echo "aaa; pdf @ entry0" | r216 program.com

# List all functions after analysis
echo "aaa; afl" | r216 program.com

# Disassemble a specific function by address
echo "aaa; pdf @ 0x0105" | r216 program.com

# Print 20 instructions at offset 0
echo "pd 20" | r216 program.com

# Show cross-references to an address
echo "aaa; axt 0x0130" | r216 program.com

# Dump strings
echo "iz" | r216 program.com

# Show imports / entry info
echo "ie" | r216 program.com

# Hex dump at offset
echo "px 64 @ 0x0" | r216 program.com

# Search for byte pattern
echo "/x cd21" | r216 program.com
```

`r216` passes `-b 16 -a x86` to radare2. Always prefix analysis commands with `aaa` (full analysis) or `aa` (basic) before using `pdf`, `afl`, or `axt`.

Interactive mode (run `r216 program.com` without piping) drops into the radare2 REPL. Avoid in automated workflows.

### dump16 (objdump)

Useful when you need Intel-syntax output or want to cross-check ndisasm.

```bash
# Full disassembly, Intel syntax
dump16 program.com

# Disassembly with hex bytes shown
dump16 --show-raw-insn program.com

# Disassemble only a section (requires ELF/COFF; .com is raw binary so -D covers all)
dump16 program.com | grep -A5 "0000:"
```

`dump16` calls `objdump -m i8086 -M intel -b binary -D`. The `-b binary` flag treats the input as a raw binary blob with no headers.

---

## Ghidra Headless

`analyzeHeadless` is symlinked to `/usr/local/bin/`. Ghidra is at `/opt/ghidra/`. JDK 21 is at `/opt/java/openjdk/` (required; already in PATH).

### Import and analyze a binary

```bash
analyzeHeadless /tmp/ghidra_projects MyProject \
  -import /workspace/program.com \
  -processor "x86:LE:16:Real Mode:default" \
  -overwrite
```

### Import, analyze, then run a post-analysis script

```bash
analyzeHeadless /tmp/ghidra_projects MyProject \
  -import /workspace/program.com \
  -processor "x86:LE:16:Real Mode:default" \
  -postScript ExportFunctions.java \
  -overwrite
```

### Export disassembly listing via built-in script

```bash
analyzeHeadless /tmp/ghidra_projects MyProject \
  -process program.com \
  -postScript /opt/ghidra/Ghidra/Features/Base/ghidra_scripts/DumpFunctionInfoScript.java \
  -noanalysis
```

Key flags:

| Flag                   | Effect                                              |
| ---------------------- | --------------------------------------------------- |
| `-import <file>`       | Import file into project                            |
| `-process <name>`      | Operate on already-imported file                    |
| `-processor <string>`  | CPU/language string (use `x86:LE:16:Real Mode:default` for DOS) |
| `-postScript <script>` | Run Ghidra script after analysis                    |
| `-overwrite`           | Replace existing imported file                      |
| `-noanalysis`          | Skip auto-analysis (use with `-process`)            |
| `-deleteProject`       | Remove project directory after run                  |

Ghidra scripts live in `/opt/ghidra/Ghidra/Features/Base/ghidra_scripts/`. Custom scripts can be placed anywhere; pass absolute path.

---

## Python: capstone and pefile

Both are installed globally (`pip3`).

### capstone: disassemble bytes directly

```python
import capstone

with open("/workspace/program.com", "rb") as f:
    code = f.read()

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_16)
md.detail = True

# Disassemble from start, virtual address 0x100 (COM load address)
for insn in md.disasm(code, 0x100):
    print(f"0x{insn.address:04x}:  {insn.mnemonic:<8} {insn.op_str}")
```

capstone constants for 16-bit: `CS_ARCH_X86`, `CS_MODE_16`. For real-mode segmented addressing, track CS:IP manually.

### pefile: parse MZ/PE headers

```python
import pefile

pe = pefile.PE("/workspace/program.exe")

# Show DOS header fields
print(hex(pe.DOS_HEADER.e_magic))   # 0x5a4d = 'MZ'
print(hex(pe.DOS_HEADER.e_lfanew))  # offset to PE header

# Iterate sections
for section in pe.sections:
    print(section.Name, hex(section.VirtualAddress), section.SizeOfRawData)

# Show imports
for entry in pe.DIRECTORY_ENTRY_IMPORT:
    for imp in entry.imports:
        print(entry.dll, imp.name)
```

For raw .com files (no MZ header), pefile will raise `PEFormatError`. Use capstone or dis16 directly on .com files.

---

## Common Workflows

### First look at a binary

```bash
# File type and size
file /workspace/program.com
ls -lh /workspace/program.com
xxd /workspace/program.com | head -4

# Quick linear disassembly
dis16 /workspace/program.com | head -60

# radare2: analyze and print entry point
echo "aaa; pdf @ entry0" | r216 /workspace/program.com
```

### Find strings

```bash
# ASCII strings (length >= 4)
strings /workspace/program.com

# In radare2 (with section context)
echo "iz" | r216 /workspace/program.com

# Search for specific DOS interrupt string patterns
strings /workspace/program.com | grep -i "dos\|error\|file"
```

### Trace execution from entry point

```bash
# List all discovered functions
echo "aaa; afl" | r216 /workspace/program.com

# Disassemble entry function
echo "aaa; pdf @ entry0" | r216 /workspace/program.com

# Follow a call target (e.g., function at 0x0120)
echo "aaa; pdf @ 0x0120" | r216 /workspace/program.com

# Show call graph
echo "aaa; agC" | r216 /workspace/program.com
```

### Find DOS interrupt calls (INT 21h)

DOS services are invoked via `int 0x21`. AH register holds the function number.

```bash
# Search for CD 21 (INT 21h opcode bytes)
echo "/x cd21" | r216 /workspace/program.com

# ndisasm: grep for int lines
dis16 /workspace/program.com | grep "int "

# capstone: collect all INT instructions
python3 - <<'EOF'
import capstone
code = open("/workspace/program.com","rb").read()
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_16)
for i in md.disasm(code, 0x100):
    if i.mnemonic == "int":
        print(f"0x{i.address:04x}: {i.mnemonic} {i.op_str}")
EOF
```

### Ghidra automated analysis and function export

```bash
analyzeHeadless /tmp/ghp MyProj \
  -import /workspace/program.com \
  -processor "x86:LE:16:Real Mode:default" \
  -overwrite -deleteProject \
  2>&1 | tee /tmp/ghidra_analysis.log
```

Review `/tmp/ghidra_analysis.log` for identified functions, data references, and auto-labels.

---

## Gotchas

| Issue                              | Cause / Fix                                                                           |
| ---------------------------------- | ------------------------------------------------------------------------------------- |
| Wrong instruction sizes decoded    | Tool defaulted to 32/64-bit mode. Always use `dis16`, `r216`, `dump16` wrappers.      |
| radare2 interactive mode hangs     | Do not run `r216 file` without piping; use `echo "cmds" \| r216 file`.               |
| ndisasm decodes data as code       | ndisasm is linear; it cannot distinguish code from data. Cross-check with r216/Ghidra.|
| pefile raises PEFormatError        | .com files have no MZ header. Use capstone or dis16 for raw binaries.                 |
| Ghidra wrong processor             | Default is x86 32-bit. Always pass `-processor "x86:LE:16:Real Mode:default"`.        |
| Ghidra project already exists      | Add `-overwrite` flag or use a fresh project path.                                    |
| Serena finds no symbols            | Serena has no binary/asm language server. It is only useful for .asm source files.    |
| COM file load address              | DOS loads .com files at offset 0x100 in the segment. Pass `-o 0x100` to dis16, and use 0x100 as the base address in capstone. |
