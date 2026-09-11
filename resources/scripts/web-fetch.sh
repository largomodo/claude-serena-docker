#!/bin/bash
# Fetch a web page as markdown with trafilatura, walking a fallback ladder so
# one call replaces the manual retry sequence in the web-fetch skill:
#
#   1. live fetch with trafilatura's own (Chrome-patched) user agent
#   2. curl with an explicit Chrome user agent, piped into trafilatura
#   3. Internet Archive snapshot (raw "id_" copy, newest available)
#
# Each stage is tried only if the previous one produced less than MIN_BYTES of
# markdown. A Cloudflare or similar JavaScript challenge page is recognised in
# stage 2 and reported by name; no user agent gets past it, so the ladder moves
# straight on to the archive. A URL fragment (#anchor) is dropped before the
# fetch; servers never see it, grep the output for the heading instead.
#
# Markdown goes to stdout, so `> /tmp/page.md` yields a clean file. One status
# line goes to stderr, prefixed "web-fetch:", naming the stage that succeeded
# and, for the archive, the snapshot date. Exit 1 with a reason when every
# stage fails; trafilatura's own log lines from the failed stages are shown
# only then.
#
# Usage:
#   web-fetch.sh <url> [trafilatura extraction flags...]
#   web-fetch.sh https://example.org/page --recall --links
#   MIN_BYTES=50 web-fetch.sh <url>      accept shorter output as success
set -uo pipefail

URL="${1:?usage: web-fetch.sh <url> [trafilatura flags...]}"
shift
FLAGS=("$@")
MIN_BYTES="${MIN_BYTES:-200}"
FALLBACK_UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36'

URL="${URL%%#*}"

command -v trafilatura >/dev/null || { echo "web-fetch: trafilatura not on PATH" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
OUT="$WORK/out.md"
LOG="$WORK/log"
RAW="$WORK/raw.html"
: > "$LOG"

# Use the user agent trafilatura itself sends so both stages present the same identity.
PYBIN="$(dirname "$(command -v trafilatura)")/python"
UA="$("$PYBIN" -c 'from trafilatura.downloads import DEFAULT_HEADERS; print(DEFAULT_HEADERS["User-Agent"])' 2>/dev/null || true)"
case "$UA" in Mozilla/*) ;; *) UA="$FALLBACK_UA" ;; esac

big_enough() { [ "$(wc -c < "$1")" -ge "$MIN_BYTES" ]; }

done_with() {
    echo "web-fetch: $1" >&2
    cat "$OUT"
    exit 0
}

# Stage 1: trafilatura live.
trafilatura -u "$URL" --markdown "${FLAGS[@]}" > "$OUT" 2>> "$LOG"
big_enough "$OUT" && done_with "live fetch ok ($(wc -c < "$OUT") bytes) $URL"

# Stage 2: curl with explicit UA, then extract. Detect JS challenge pages.
HTTP_CODE="$(curl -sL --compressed -A "$UA" --max-time 30 -o "$RAW" -w '%{http_code}' "$URL" 2>> "$LOG")"
[ -n "$HTTP_CODE" ] || HTTP_CODE=000
CHALLENGE=""
if grep -q -i -E 'cf-chl|cf_chl|challenge-platform|Just a moment\.\.\.|_cf_chl_opt|Attention Required! \| Cloudflare|Checking your browser' "$RAW" 2>/dev/null; then
    CHALLENGE="cloudflare/javascript challenge"
elif grep -q -i -E 'captcha|access denied|are you a robot|enable javascript' "$RAW" 2>/dev/null && [ "$(wc -c < "$RAW")" -lt 20000 ]; then
    CHALLENGE="bot check page"
fi
if [ -z "$CHALLENGE" ] && [ "$HTTP_CODE" = "200" ]; then
    trafilatura --markdown "${FLAGS[@]}" < "$RAW" > "$OUT" 2>> "$LOG"
    big_enough "$OUT" && done_with "curl+UA fetch ok ($(wc -c < "$OUT") bytes) $URL"
fi
LIVE_REASON="http $HTTP_CODE${CHALLENGE:+, $CHALLENGE}"

# Stage 3: newest Internet Archive snapshot, raw copy without the Wayback toolbar.
LOCATION="$(curl -sI --max-time 30 "https://web.archive.org/web/2/$URL" 2>> "$LOG" | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}' | tail -1)"
STAMP="$(printf '%s' "$LOCATION" | sed -n 's|.*/web/\([0-9]\{14\}\)/.*|\1|p')"
if [ -n "$STAMP" ]; then
    SNAP_URL="https://web.archive.org/web/${STAMP}id_/$URL"
    SNAP_DATE="${STAMP:0:4}-${STAMP:4:2}-${STAMP:6:2}"
    # "id_" serves the stored bytes untouched, which includes the original
    # Content-Encoding, so curl must decompress.
    curl -sL --compressed -A "$UA" --max-time 60 -o "$RAW" "$SNAP_URL" 2>> "$LOG"
    trafilatura --markdown "${FLAGS[@]}" < "$RAW" > "$OUT" 2>> "$LOG"
    big_enough "$OUT" && done_with "ARCHIVE snapshot $SNAP_DATE ($(wc -c < "$OUT") bytes); live fetch failed: $LIVE_REASON. $SNAP_URL"
    ARCHIVE_REASON="snapshot $SNAP_DATE extracted to $(wc -c < "$OUT") bytes (< MIN_BYTES=$MIN_BYTES)"
else
    ARCHIVE_REASON="no snapshot in the Internet Archive"
fi

{
    echo "web-fetch: FAILED $URL"
    echo "  live: $LIVE_REASON"
    echo "  archive: $ARCHIVE_REASON"
    if [ -n "$CHALLENGE" ]; then
        echo "  the site requires a JavaScript challenge; trafilatura cannot run JavaScript. Report this to the user."
    elif [ -s "$RAW" ] && [ "$(wc -c < "$RAW")" -lt 2000 ]; then
        echo "  raw body is $(wc -c < "$RAW") bytes; likely a JavaScript-only page or a block page."
    fi
    if [ -s "$LOG" ]; then echo "  trafilatura/curl log:"; sed 's/^/    /' "$LOG"; fi
} >&2
exit 1
