#!/bin/bash
# Make a current desktop Chrome user agent trafilatura's default.
#
# trafilatura sends "trafilatura/<ver> (+github url)" by default and some
# publishers (spiegel.de) answer that with 403. The USER_AGENTS option in its
# settings.cfg is only honoured for a config that differs from the built-in
# default, so plain CLI use, the Python API, and feed/sitemap/crawl discovery
# all keep the crawler identity. The one line that sets it for those paths is
#
#     DEFAULT_HEADERS["User-Agent"] = USER_AGENT        (downloads.py)
#
# unchanged in every release since v1.12.0. This script rewrites that line to
# assign the Chrome string, and also fills USER_AGENTS in settings.cfg so a
# config copied from the default inherits it.
#
# Chrome major: Google's Chrome for Testing endpoint. Real Chrome reports
# MAJOR.0.0.0 (UA reduction), so only the major is used. If the lookup fails
# the fallback major is used and the build continues with a warning.
#
# FAIL PATH: if the target line is missing, or the effective header after the
# edit is not the Chrome string, the script prints what it found and how to fix
# it, and exits 1 so the image build stops instead of shipping the crawler UA.
#
# Usage:
#   trafilatura-ua.sh <venv-python>           patch (build time)
#   trafilatura-ua.sh --check <venv-python>   print the effective default UA
set -euo pipefail

FALLBACK_MAJOR="${CHROME_MAJOR_FALLBACK:-153}"
ENDPOINT="https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions.json"
TARGET='DEFAULT_HEADERS["User-Agent"] = USER_AGENT'

effective_ua() {
    "$1" -c 'from trafilatura.downloads import DEFAULT_HEADERS; print(DEFAULT_HEADERS["User-Agent"])'
}

if [ "${1:-}" = "--check" ]; then
    PY="${2:?usage: trafilatura-ua.sh --check <venv-python>}"
    effective_ua "$PY"
    exit 0
fi

PY="${1:?usage: trafilatura-ua.sh <venv-python>}"

fail() {
    cat >&2 <<MSG
error: trafilatura user agent patch failed.
  $1
  trafilatura version: $("$PY" -c 'import trafilatura;print(trafilatura.__version__)' 2>/dev/null || echo unknown)
  file: ${DL:-unknown}
  Without this patch trafilatura identifies itself as a crawler and some sites
  answer 403. To fix: open the file above, find where the default User-Agent
  header is assigned, and update TARGET / the sed pattern in
  resources/scripts/trafilatura-ua.sh. To build without the patch anyway, set
  the build-arg TRAFILATURA_UA_PATCH=skip (the web-fetch skill's curl fallback
  still works).
MSG
    exit 1
}

if [ "${TRAFILATURA_UA_PATCH:-}" = "skip" ]; then
    echo "warning: trafilatura user agent patch skipped (TRAFILATURA_UA_PATCH=skip); crawler UA stays." >&2
    exit 0
fi

MAJOR="$(curl -fsSL --max-time 20 "$ENDPOINT" | jq -r '.channels.Stable.version' | cut -d. -f1 || true)"
if ! [[ "$MAJOR" =~ ^[0-9]+$ ]]; then
    echo "warning: Chrome version lookup failed, using fallback major ${FALLBACK_MAJOR}" >&2
    MAJOR="$FALLBACK_MAJOR"
fi
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${MAJOR}.0.0.0 Safari/537.36"

PKG_DIR="$("$PY" -c 'import trafilatura,os;print(os.path.dirname(trafilatura.__file__))')" \
    || fail "cannot import trafilatura with $PY"
DL="$PKG_DIR/downloads.py"
CFG="$PKG_DIR/settings.cfg"

# Idempotent: a previous run already replaced the target line.
if grep -qF '# patched by trafilatura-ua.sh' "$DL"; then
    sed -i "s|^DEFAULT_HEADERS\[\"User-Agent\"\] = .*|DEFAULT_HEADERS[\"User-Agent\"] = \"${UA}\"  # patched by trafilatura-ua.sh|" "$DL"
else
    grep -qF "$TARGET" "$DL" || fail "expected line not found: $TARGET"
    sed -i "s|^DEFAULT_HEADERS\[\"User-Agent\"\] = USER_AGENT$|DEFAULT_HEADERS[\"User-Agent\"] = \"${UA}\"  # patched by trafilatura-ua.sh|" "$DL"
fi

grep -q '^USER_AGENTS *=' "$CFG" || fail "USER_AGENTS option not found in settings.cfg"
sed -i "s|^USER_AGENTS *=.*|USER_AGENTS = ${UA}|" "$CFG"

EFFECTIVE="$(effective_ua "$PY" 2>&1)" || fail "module import failed after edit: ${EFFECTIVE}"
[ "$EFFECTIVE" = "$UA" ] || fail "effective User-Agent is '${EFFECTIVE}', expected '${UA}'"

echo "trafilatura user agent: ${UA}"
