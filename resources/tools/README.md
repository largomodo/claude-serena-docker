# resources/tools/

## Overview

Sheets in this directory are imported into every Claude Code session and
every custom sub-agent in a claude-env container, via
`~/.claude/claude-env.md`. They are indexes, not manuals: `## Tools` and
`## Environment` tables list what exists; workflow detail lives in
`<variant>-notes.md` pointer files opened on demand.

## Architecture

`base.md` plus the active variant's `<variant>.md` are concatenated at
variant build time into `/usr/local/share/claude-env/claude-env.md`.
`resources/scripts/init-workspace.sh` copies that file to
`~/.claude/claude-env.md` on every launch and aborts the launch if the
image has none. claude-config's root `CLAUDE.md` (= `~/.claude/CLAUDE.md`)
imports it with a relative `@claude-env.md`, so only the `~/.claude` copy
resolves; any other loaded copy of that `CLAUDE.md` dangles harmlessly.
`<variant>-notes.md` files are staged under
`/usr/local/share/claude-env/tools/` and referenced from a sheet's
`## Notes` section with a read-when trigger.

## Format contract

Headings starting `## Tools` or `## Environment` are machine-checked
tables whose first cell holds backticked names (a cell may hold several
names). Binaries are checked with `command -v`; variables must be set and
non-empty -- a set-but-empty export fails the same as unset. `## MCP
servers` and `## Notes` sections are free-form and unchecked. `VARIANT`
belongs in every variant sheet's `## Environment` table, never in
`base.md` (it is unset when `base.md` is checked alone in the base image).
Inside a checked section, table rows are tracked by position -- the first
`|` line is the header, the next must be a well-formed `|---` separator,
and every row after that must have a first cell yielding at least one
non-empty backticked token (a Tools token containing whitespace or a
slash is rejected as malformed rather than checked) -- so a row can never
sit in a checked section without being checked, and `check-tools.sh`
reports and fails the build on any row, separator, or backticked
non-table line that breaks this shape.

## Token budget

Hard caps: 400 tokens for `base.md`, 400 tokens per `<variant>.md`, 800
tokens for the concatenated `claude-env.md`, measured with tiktoken's
`cl100k_base` encoding, which ships in Serena's venv (`python3` in every
image):

```bash
python3 -c "import tiktoken,sys; print(len(tiktoken.get_encoding('cl100k_base').encode(open(sys.argv[1]).read())))" resources/tools/base.md
```

Tokens, not words: backticked tables run roughly 1.8-2.2 tokens per word,
so a word-count cap cannot enforce this budget.

## Design decisions

Ownership split: claude-env owns sheet content, claude-config owns only
the import hook line -- claude-config is also used on plain hosts and must
stay mergeable with upstream. Two-layer concat: `base.md` plus one
`<variant>.md` avoids thirteen independent copies of the shared toolchain.
`check-tools.sh` has no skip flag: a mismatch always means either the
Dockerfile dropped a tool or the sheet names a phantom, and the fix is a
one-line edit either way. It also stays in the final image so it doubles
as the runtime diagnostic (`check-tools.sh ~/.claude/claude-env.md`).
Notes files exist only where a variant's workflow detail would blow the
400-token budget. Python libraries (capstone, pefile, pcbnew) are
documented as prose in `## Notes`, not machine-checked.
arduino.md is a case in point: with only the Tools/Environment tables and
a handful of Notes lines it is already close to its 400-token allowance, so
its FQBN, permission, clangd and simavr recipes live in arduino-notes.md
instead.

A visible mirror pointer (each notes file names its source; each mirrored
source location names the notes file) is the cheapest edit-time guard for
prose that is not machine-checked: eight variants' sheets are imported into
every session while their source directories (README.md, resources/snippets)
are not, so an editor of either side needs a pointer to the other to keep
them in sync.

`android-notes.md` is a member of the mirrored set; its README counterparts are the `android:` Troubleshooting subsections.

`android.md` uses a two-column Tools table with clustered multi-name rows: the format contract only requires backticked names in the first cell, and a third column pushes the sheet past the 400-token cap (800 combined with `base.md`) while two columns fit.

## Why delivery works this way

The sheet is delivered by an `@claude-env.md` import in claude-config's
CLAUDE.md, never by instructing agents to `cat` the file: an instruction
is something a model can skip or forget, while an import is expanded by
Claude Code into memory before the agent sees the prompt, so delivery does
not depend on model compliance.

`init-workspace.sh` copies the staged sheet to `~/.claude/claude-env.md` on
every launch, not only on first launch: `.claudeproject`/`~/.claude` persist
across image rebuilds, so a first-launch-only copy would leave a stale
sheet in place after the image (and its tool sheet) changed underneath it.
An unconditional `cp` is idempotent and costs nothing when the sheet is
already current.

Environment variables and MCP server names are listed explicitly because
neither is visible on `PATH`: a `command -v` probe finds binaries but
cannot discover that `DOCKER_HOST` must be set or that a `kicad` MCP server
is registered, so the sheet is the only place an agent can learn either
fact.

Hand-written wording (version numbers, flags, prose) can drift from the
toolchain it describes; only presence or absence of a binary or variable is
machine-checked by `check-tools.sh`. This is an accepted tradeoff -- catching
wording drift would require parsing tool output, not just checking `PATH`
and the environment -- and it is offset by the invariant that a Dockerfile
change and its sheet change land in the same commit.

## Invariants

A Dockerfile change that adds or removes a binary or environment variable
edits the matching sheet in the same commit (build-enforced in both
directions). The concat+check `RUN` stays the last `RUN` in every variant
Dockerfile, after `USER codeuser` and after every `ENV` line (`Dockerfile.base`
checks `base.md` after its own final `ENV` lines). Sheets describe the
container image, never the project mounted at /workspace.

Notes-file source map (edit-time pointers only, not machine-checked):

| Notes file | Mirrors |
| --- | --- |
| `java-docker-notes.md` | README.md Troubleshooting `java-docker:` subsections |
| `gowin-notes.md` | README.md Troubleshooting `gowin:` subsections |
| `kicad-notes.md` | README.md Troubleshooting `kicad:` subsections |
| `java-angular-notes.md` | README.md Usage > 3. Launch java-angular caveat note and Persistence npm-cache bullet (no Troubleshooting entries exist) |
| `snes-notes.md` | resources/snippets/snes/snes-analyze.sh usage text and resources/snippets/snes/CLAUDE.md (README.md has no snes content) |
| `arduino-notes.md` | README.md Troubleshooting `arduino:` subsections |
| `rea-notes.md` | README.md Troubleshooting `x86 / 68k / android:` subsections (one notes file staged by three variants) |
| `android-notes.md` | README.md Troubleshooting `android:` subsections (host adb server and relay, frida-server and mitmproxy, blutter/Il2CppDumper/JADX timeouts); staged by Dockerfile.android with android.md |

Renaming or removing both machine-checked headings from a sheet does not silently disable the check: check-tools.sh treats zero checked tokens across all concatenated files as a failure and names the sheet responsible.

Adding a variant: add a corresponding `<variant>.md` row to `resources/tools/CLAUDE.md`, and a `<variant>-notes.md` row when the variant needs one.

## Verification

Delivery is an `@claude-env.md` import in claude-config's CLAUDE.md, which Claude Code expands into memory before an agent sees the prompt -- this cannot be unit-tested inside the build, so it is confirmed with two launches:

- Variant container: launch a variant image, dispatch a no-tools probe sub-agent that quotes a tool name that exists only in that variant's sheet, and confirm `/memory` lists `~/.claude/claude-env.md` as an imported file exactly once.
- Plain host (no container): start a session and confirm the missing import target is harmless -- no import error, and `/memory` shows no `claude-env.md` entry.
