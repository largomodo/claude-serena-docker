# claude-env container toolchain: c

## Tools (c)

| Tool | What | Use when |
| --- | --- | --- |
| `clangd` | apt clangd; Serena's C/C++ language server via ls_path | Checking a translation unit outside Serena (`clangd --check`) |

## Environment (c)

| Variable | What |
| --- | --- |
| `VARIANT` | Container variant name (`c`) |

## Notes (c)

- The C toolchain is the base image's `gcc`/`g++`/`make`.
- No cmake or gdb is baked in; install with `sudo apt-get install` when needed.
