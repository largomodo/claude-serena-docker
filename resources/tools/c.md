# claude-env container toolchain: c

## Environment (c)

| Variable | What |
| --- | --- |
| `VARIANT` | Container variant name (`c`) |

## Notes (c)

- The C toolchain is the base image's `gcc`/`g++`/`make`.
- clangd is downloaded by Serena on first use; retry indexing if it warns.
- No cmake or gdb is baked in; install with `sudo apt-get install` when needed.
