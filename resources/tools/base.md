# claude-env container toolchain

Describes the container image, not /workspace. Every listed binary is
confirmed on PATH at build time.

## Tools (all variants)

| Tool | What | Use when |
| --- | --- | --- |
| `git` `gcc` `g++` `make` `python3` `uv` `node` `npm` `curl` `shellcheck` | Standard toolchain | Build, compile, manage deps, lint shell |
| `rg` `fdfind` `jq` `yq` | Search + JSON/YAML query (`fd`=`fdfind`) | Search code/text, filter data |
| `web-fetch.sh` `http` | trafilatura fetch; HTTPie | Read a page (WebFetch denied); raw HTTP |
| `pandoc` `pdftotext` `tesseract` | Doc/PDF/image text extraction | Convert formats, extract PDF text, OCR |
| `sqlite3` `litecli` `psql` `pgcli` `csvlook` `csvsql` | DB/CSV clients | Query sqlite/Postgres, inspect CSV |
| `magick` `ffmpeg` `dot` | Image/media/graph rendering | Convert media, render a Graphviz diagram |

## Environment (all variants)

| Variable | What |
| --- | --- |
| `SERENA_HOME` | Serena data dir |

## Notes (all variants)

- MCP `serena` (LSP code navigation) is registered for /workspace in every variant.
- `python` is Serena's venv (no pip); `pip` is the cli-tools venv's; install into neither -- use `uv venv`/`uvx` or `sudo apt-get install`.
- Runtime state lives under /workspace/.claudeproject.
- `VARIANT` is absent here (unset for base alone); each variant sheet's own table lists it.
