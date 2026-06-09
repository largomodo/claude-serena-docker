#!/usr/bin/env python3
"""Headless Specctra DSN export / SES import via the pcbnew SWIG bindings.

KiCad 9's kicad-cli has no specctra subcommand, so DSN export and SES import must
go through pcbnew -- the same SWIG backend the MCP already uses (ref: KI-007).
This helper loads a .kicad_pcb, then either writes a .dsn (for freerouting) or
applies a routed .ses and saves the board.

Run it with the interpreter that can see pcbnew (the MCP venv, ref: KI-001):

    /opt/kicad-mcp/.venv/bin/python kicad_specctra.py export <board.kicad_pcb> <out.dsn>
    /opt/kicad-mcp/.venv/bin/python kicad_specctra.py import <board.kicad_pcb> <in.ses> [out.kicad_pcb]

The pcbnew API for these calls has varied across KiCad versions: the function names
themselves have drifted (KiCad 9.0 exposes ImportSpecctraSES; older/other builds used
ImportSpecctraSession), and the signature is sometimes (board, path), sometimes (path)
bound to the GUI's active board. We resolve the name from a candidate list and try the
robust signatures in order, failing loudly rather than silently producing nothing.
"""
import os
import sys

import pcbnew

# Candidate symbol names per operation, in preference order. KiCad 9.0 = first entry.
EXPORT_FNS = ("ExportSpecctraDSN",)
IMPORT_FNS = ("ImportSpecctraSES", "ImportSpecctraSession")


def _resolve(names):
    """Return the first pcbnew attribute that exists from `names`, else None."""
    for name in names:
        fn = getattr(pcbnew, name, None)
        if fn is not None:
            return fn
    return None


def _call_variants(fn, board, path):
    """Try fn(board, path) then fn(path); succeed on any call that doesn't report False."""
    errors = []
    for args in ((board, path), (path,)):
        try:
            result = fn(*args)
        except TypeError as exc:
            errors.append(f"{fn.__name__}{args!r}: {exc}")
            continue
        # Some versions return None (void), others a bool. Treat non-False as success.
        if result is not False:
            return
        errors.append(f"{fn.__name__}{args!r} returned False")
    raise RuntimeError("; ".join(errors))


def export_dsn(board_path, dsn_path):
    board = pcbnew.LoadBoard(board_path)
    fn = _resolve(EXPORT_FNS)
    if fn is None:
        sys.exit(f"pcbnew exposes none of {EXPORT_FNS}; this KiCad build lacks SWIG specctra export")
    try:
        _call_variants(fn, board, dsn_path)
    except RuntimeError as exc:
        sys.exit(f"DSN export failed: {exc}")
    if not os.path.isfile(dsn_path):
        sys.exit(f"{fn.__name__} reported success but {dsn_path} was not written")
    print(f"DSN exported: {dsn_path}")


def import_ses(board_path, ses_path, out_path):
    board = pcbnew.LoadBoard(board_path)
    fn = _resolve(IMPORT_FNS)
    if fn is None:
        sys.exit(f"pcbnew exposes none of {IMPORT_FNS}; this KiCad build lacks SWIG specctra import")
    try:
        _call_variants(fn, board, ses_path)
    except RuntimeError as exc:
        sys.exit(f"SES import failed: {exc}")
    if not pcbnew.SaveBoard(out_path, board):
        sys.exit(f"Failed to save routed board to {out_path}")
    print(f"Routed board written: {out_path}")


def main(argv):
    if len(argv) < 4:
        sys.exit(__doc__)
    cmd = argv[1]
    if cmd == "export" and len(argv) == 4:
        export_dsn(argv[2], argv[3])
    elif cmd == "import" and len(argv) in (4, 5):
        out = argv[4] if len(argv) == 5 else argv[2]
        import_ses(argv[2], argv[3], out)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
