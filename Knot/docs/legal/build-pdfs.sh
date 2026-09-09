#!/bin/bash
#
# Render the Knot legal documents to PDF, for hosting somewhere that serves files
# rather than web pages (currently Google Drive).
#
#   ./build-pdfs.sh [out-dir] [privacy-url] [terms-url]
#
# The HTML pages in this directory are the source of truth. This script never edits
# them — it renders a temporary copy so the repo stays host-agnostic.
#
# Two transformations are applied to that copy, and both exist for a reason:
#
#   1. FONTS. The pages use the `-apple-system` stack, which resolves to SF Pro and
#      gets embedded, producing ~700KB PDFs. Substituting Helvetica cuts roughly 25%
#      (697KB -> 519KB) with no visible difference at body sizes. Chrome still embeds
#      a subset of Helvetica rather than relying on the reader's base-14 copy — the
#      saving is that Helvetica's subset is far smaller than SF Pro's, not that the
#      font is omitted.
#
#   2. CROSS-LINKS. Each page links the other with the site-absolute paths `/privacy`
#      and `/terms`. Those resolve only at a domain root — inside a standalone PDF they
#      are dead links. Passing the two hosted URLs rewrites them so the PDFs point at
#      each other wherever they actually live. Omit them and the links stay dead, which
#      is fine for a proof render but not for anything published.
#
# Requires Google Chrome (headless). No other dependency.
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$SRC/build}"
PRIVACY_URL="${2:-}"
TERMS_URL="${3:-}"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ ! -x "$CHROME" ]; then
  echo "error: Google Chrome not found at $CHROME" >&2
  echo "       Chrome provides the headless PDF renderer this script uses." >&2
  exit 1
fi

if { [ -n "$PRIVACY_URL" ] && [ -z "$TERMS_URL" ]; } ||
   { [ -z "$PRIVACY_URL" ] && [ -n "$TERMS_URL" ]; }; then
  echo "error: pass both URLs or neither — a half-rewritten pair leaves one dead link." >&2
  exit 1
fi

# Escape a URL for the right-hand side of a sed s||| replacement. Drive share links
# routinely carry `&` (e.g. ?usp=sharing&…), which sed would otherwise expand to the
# whole match and silently corrupt the href.
sed_replacement() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

for page in privacy terms; do
  sed -E 's/font-family: -apple-system[^;]*;/font-family: Helvetica, Arial, sans-serif;/' \
    "$SRC/$page.html" > "$TMP/$page.html"

  if [ -n "$PRIVACY_URL" ]; then
    privacy_replacement="$(sed_replacement "$PRIVACY_URL")"
    terms_replacement="$(sed_replacement "$TERMS_URL")"
    sed -i '' \
      -e "s|href=\"/privacy\"|href=\"$privacy_replacement\"|g" \
      -e "s|href=\"/terms\"|href=\"$terms_replacement\"|g" \
      "$TMP/$page.html"
  fi
done

# Chrome exits 0 even when it fails to write the PDF, so the output has to be checked
# directly. Removing any previous file first means a failed re-render can never leave a
# stale PDF behind to be reported as success and uploaded.
render() {
  local page="$1" name="$2" out="$OUT/$2"
  rm -f "$out"
  "$CHROME" --headless=new --disable-gpu --no-pdf-header-footer \
    --print-to-pdf="$out" "file://$TMP/$page.html" >/dev/null 2>&1
  if [ ! -s "$out" ] || [ "$(head -c 4 "$out")" != "%PDF" ]; then
    echo "error: Chrome did not write a valid PDF to $out" >&2
    exit 1
  fi
  echo "  $name  ($(du -h "$out" | cut -f1))"
}

echo "Rendering to $OUT"
render privacy "Knot-Privacy-Policy.pdf"
render terms   "Knot-Terms-of-Service.pdf"

if [ -z "$PRIVACY_URL" ]; then
  echo
  echo "note: rendered without hosted URLs, so the cross-links between the two"
  echo "      documents are dead. Re-run with both URLs before publishing."
fi
