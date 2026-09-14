#!/bin/bash
# check-tools.sh -- build-time guard for claude-env tool sheets.
#
# Usage: check-tools.sh <sheet.md> [<sheet.md>...]
#
# Format contract: a `## Tools` heading (case-insensitive) enters TOOLS
# mode, a `## Environment` heading (case-insensitive) enters ENV mode, any
# other `## ` heading leaves both. Inside either mode, table rows are
# tracked by position, not content: the first `|` line is the header
# (exempt), the next `|` line must be a well-formed `|---` separator
# (exempt), and every `|` line after that is a data row whose first cell's
# backticked tokens are collected (a cell may hold several names, e.g.
# `nasm` `ndisasm`). A data row whose first cell yields no non-empty
# backticked token -- including one holding only empty backtick pairs --
# is reported as an unchecked row and fails the build, so a row can never
# sit in a checked section without being checked. A `|` line in the
# separator position that is not a well-formed separator (a second
# header, a stray data row before the real separator) fails the same way.
# A Tools token containing whitespace or a slash is rejected as malformed
# rather than handed to `command -v`. `## MCP servers` and `## Notes`
# sections are free-form and never parsed.
# A `## Tools` or `## Environment` section that matches its heading but
# yields zero checkable rows -- e.g. a reformatted table missing its
# leading `|` -- fails the build for that section, so a malformed table in
# one sheet cannot hide behind a nonzero count from another sheet. Inside
# a checked section, any non-blank line containing a backtick must itself
# be a well-formed table row (leading `|` once whitespace is stripped), or
# the checker reports the unparsed line and fails, so one malformed row
# cannot hide behind other well-formed rows in the same section.
#
# TOOLS tokens are resolved with `command -v`; ENV tokens must be set AND
# non-empty (`[ -n "${!name:-}" ]`) -- a set-but-empty variable behaves like
# unset for every consumer the sheets name.
#
# No skip flag: the sheet is imported into every agent session, so
# a tool it names must exist; the fix is always a one-line edit to the sheet
# or the Dockerfile, never a build override.
#
# This script stays in the final image at /usr/local/bin: every
# variant build calls it, and `check-tools.sh ~/.claude/claude-env.md` is
# also the runtime diagnostic for "agents do not mention container tools".
set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "usage: check-tools.sh <sheet.md> [<sheet.md>...]" >&2
    exit 1
fi

missing_binaries=()
missing_vars=()
empty_sections=()
unparsed_lines=()
unchecked_rows=()
malformed_tokens=()
checked_tools=0
checked_vars=0
mode="none"
mode_label=""
section_count=0
row_state="header"
sheet=""

extract_backticked() {
    # Prints every `backticked` token found in the first `|`-delimited cell of $1.
    local cell="$1"
    # shellcheck disable=SC2016  # backticks below are literal data, not command substitution
    grep -o '`[^`]*`' <<<"$cell" | tr -d '`'
}

check_name() {
    # Records $2 as missing if it is a tools-mode binary not on PATH, or an
    # env-mode variable that is unset or empty.
    local check_mode="$1" name="$2"
    [ -z "$name" ] && return 0
    section_count=$((section_count + 1))
    if [ "$check_mode" = "tools" ]; then
        checked_tools=$((checked_tools + 1))
        command -v "$name" >/dev/null 2>&1 || missing_binaries+=("$name ($sheet)")
    else
        checked_vars=$((checked_vars + 1))
        [ -n "${!name:-}" ] || missing_vars+=("$name ($sheet)")
    fi
}

close_section() {
    # Records an error if the section just left matched a `## Tools` or
    # `## Environment` heading but never collected a single checkable row --
    # a reformatted table (e.g. rows missing their leading `|`) that the
    # heading match alone cannot catch.
    if [ "$mode" != "none" ] && [ "$section_count" -eq 0 ]; then
        empty_sections+=("## $mode_label ($sheet)")
    fi
}

check_line() {
    # Advances $mode on a `## ` heading (case-insensitive), otherwise checks
    # every backticked token in the line's first table cell against the
    # current mode.
    local line="$1" lower
    lower="${line,,}"
    case "$lower" in
        "## tools"*)
            close_section
            mode="tools"
            mode_label="Tools"
            section_count=0
            row_state="header"
            return
            ;;
        "## environment"*)
            close_section
            mode="env"
            mode_label="Environment"
            section_count=0
            row_state="header"
            return
            ;;
        "## "*)
            close_section
            mode="none"
            mode_label=""
            section_count=0
            return
            ;;
    esac

    [ "$mode" = "none" ] && return 0

    local trimmed="$line"
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
    case "$trimmed" in
        '|'*) ;;
        *)
            case "$trimmed" in
                *'`'*) unparsed_lines+=("unparsed line in ## $mode_label ($sheet): $line") ;;
            esac
            return 0
            ;;
    esac

    case "$row_state" in
        header)
            # The first `|` line in the section is the header; exempt
            # regardless of content.
            row_state="separator"
            return 0
            ;;
        separator)
            # The second `|` line must be a genuine `|---|---|` separator:
            # stripping every `|`, `:`, `-`, and space leaves nothing only
            # for a real separator row. Anything else here -- a second
            # header, a data row with no separator in between -- is a
            # malformed table and fails the build like any other unparsed
            # line.
            local stripped="${trimmed//[-:| ]/}"
            if [ -n "$stripped" ]; then
                unparsed_lines+=("unparsed line in ## $mode_label ($sheet): $line")
                return 0
            fi
            row_state="data"
            return 0
            ;;
    esac

    local first_cell found
    first_cell="$(cut -d'|' -f2 <<<"$trimmed")"
    found=0

    while IFS= read -r name; do
        [ -z "$name" ] && continue
        found=1
        if [ "$mode" = "tools" ]; then
            case "$name" in
                *[[:space:]]*|*/*)
                    malformed_tokens+=("malformed tool token \`$name\` in ## $mode_label ($sheet): $line")
                    continue
                    ;;
            esac
        fi
        check_name "$mode" "$name"
    done < <(extract_backticked "$first_cell")

    [ "$found" -eq 0 ] && unchecked_rows+=("unchecked row in ## $mode_label ($sheet): $line")
    return 0
}

check_sheet() {
    # Resets mode per sheet and checks every line of $1 in turn.
    sheet="$1"
    mode="none"
    mode_label=""
    section_count=0
    row_state="header"
    while IFS= read -r line; do
        check_line "$line"
    done < "$sheet"
    close_section
}

for sheet in "$@"; do
    check_sheet "$sheet"
done

if [ "${#empty_sections[@]}" -gt 0 ] || [ "${#unparsed_lines[@]}" -gt 0 ] \
    || [ "${#unchecked_rows[@]}" -gt 0 ] || [ "${#malformed_tokens[@]}" -gt 0 ]; then
    echo "error: claude-env tool sheet mismatch" >&2
    for s in "${empty_sections[@]}"; do
        echo "  no rows found in $s" >&2
    done
    for u in "${unparsed_lines[@]}"; do
        echo "  $u" >&2
    done
    for r in "${unchecked_rows[@]}"; do
        echo "  $r" >&2
    done
    for t in "${malformed_tokens[@]}"; do
        echo "  $t" >&2
    done
    echo "  a table row must start with '|' once leading whitespace is" >&2
    echo "  stripped; a section matching its heading with zero rows is" >&2
    echo "  treated the same as a missing heading; a backticked line that" >&2
    echo "  is not a well-formed row, or a data row whose first cell has" >&2
    echo "  no backticked token, is reported instead of skipped; and a" >&2
    echo "  Tools token with whitespace or a slash is rejected as" >&2
    echo "  malformed instead of being passed to command -v." >&2
    exit 1
fi

if [ "$((checked_tools + checked_vars))" -eq 0 ]; then
    echo "error: claude-env tool sheet mismatch" >&2
    echo "  no \`## Tools\` or \`## Environment\` table rows found in: $*" >&2
    echo "  a heading rename or a table reformat has silently disabled the check." >&2
    exit 1
fi

if [ "${#missing_binaries[@]}" -gt 0 ] || [ "${#missing_vars[@]}" -gt 0 ]; then
    echo "error: claude-env tool sheet mismatch" >&2
    for b in "${missing_binaries[@]}"; do
        echo "  missing binary: $b" >&2
    done
    for v in "${missing_vars[@]}"; do
        echo "  unset or empty variable: $v" >&2
    done
    echo "  Either the Dockerfile dropped the tool, or the sheet names one that" >&2
    echo "  was never installed. Edit resources/tools/<variant>.md or the" >&2
    echo "  Dockerfile -- the sheet is imported into every agent session, so it" >&2
    echo "  must never name an absent tool." >&2
    exit 1
fi

echo "check-tools: ${checked_tools} binaries and ${checked_vars} variables verified"
