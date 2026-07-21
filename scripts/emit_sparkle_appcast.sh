#!/bin/bash
# Emit Skagway.appcast.xml for Sparkle from a notarized Skagway.dmg.
#
# Usage:
#   bash scripts/emit_sparkle_appcast.sh path/to/Skagway.dmg [output-dir]
#
# Defaults:
#   output-dir = dist/
#   feed URL prefix = https://downloads.machiilabs.com/
#   Keychain account = machiilabs.skagway (or --ed-key-file secrets/sparkle_ed25519)
#
# Prerequisites: Sparkle tools from SPM (DerivedData) or SPARKLE_BIN pointing at …/Sparkle/bin

set -euo pipefail

cd "$(dirname "$0")/.."

DMG_PATH="${1:?Usage: $0 path/to/Skagway.dmg [output-dir]}"
OUT_DIR="${2:-dist}"
DOWNLOAD_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://downloads.machiilabs.com/}"
KEY_ACCOUNT="${SPARKLE_KEYCHAIN_ACCOUNT:-machiilabs.skagway}"
PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-secrets/sparkle_ed25519}"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

find_sparkle_bin() {
  if [[ -n "${SPARKLE_BIN:-}" && -x "${SPARKLE_BIN}/generate_appcast" ]]; then
    echo "$SPARKLE_BIN"
    return 0
  fi
  local candidate
  candidate=$(find "${HOME}/Library/Developer/Xcode/DerivedData" \
    -path '*/artifacts/sparkle/Sparkle/bin/generate_appcast' 2>/dev/null | head -1 || true)
  if [[ -n "$candidate" ]]; then
    dirname "$candidate"
    return 0
  fi
  return 1
}

if ! SPARKLE_TOOLS=$(find_sparkle_bin); then
  echo "Sparkle tools not found. Build the app once (to resolve SPM) or set SPARKLE_BIN to …/Sparkle/bin" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/skagway-appcast.XXXXXX")
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Stable enclosure name matches the public download URL basename.
cp -f "$DMG_PATH" "${WORK}/Skagway.dmg"

GEN_ARGS=(
  --account "$KEY_ACCOUNT"
  --download-url-prefix "$DOWNLOAD_PREFIX"
  -o Skagway.appcast.xml
)

if [[ -f "$PRIVATE_KEY_FILE" ]]; then
  GEN_ARGS+=(--ed-key-file "$PRIVATE_KEY_FILE")
fi

echo "Generating appcast with ${SPARKLE_TOOLS}/generate_appcast…"
"${SPARKLE_TOOLS}/generate_appcast" "${GEN_ARGS[@]}" "$WORK"

cp -f "${WORK}/Skagway.appcast.xml" "${OUT_DIR}/Skagway.appcast.xml"
# Also copy the enclosure sibling used for the feed (same bytes as input DMG).
cp -f "${WORK}/Skagway.dmg" "${OUT_DIR}/Skagway.dmg"

echo "✓ Appcast: ${OUT_DIR}/Skagway.appcast.xml"
echo "  Enclosure URL: ${DOWNLOAD_PREFIX}Skagway.dmg"
echo "  Publish both files to downloads.machiilabs.com (see docs/SPARKLE.md)."
