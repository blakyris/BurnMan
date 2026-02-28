#!/usr/bin/env bash
#
# bundle-xorriso.sh — Bundle xorriso from Homebrew for BurnMan
#
# xorriso has no Homebrew dylib dependencies (only /usr/lib/*),
# so we just copy the binary and ad-hoc sign it.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_DIR="${PROJECT_DIR}/BurnMan/Resources/xorriso-bundle"

# ---------- colours ----------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# ---------- Step 1: locate xorriso ------------------------------------------
XORRISO_PATH="$(which xorriso 2>/dev/null || true)"

if [ -z "$XORRISO_PATH" ]; then
    error "xorriso not found. Install it with: brew install xorriso"
fi

info "Found xorriso at: ${XORRISO_PATH}"

# ---------- Step 2: copy binary ----------------------------------------------
info "Copying xorriso into bundle..."
mkdir -p "$BUNDLE_DIR"
cp "$XORRISO_PATH" "${BUNDLE_DIR}/xorriso"
chmod +x "${BUNDLE_DIR}/xorriso"

# ---------- Step 3: verify no Homebrew dylib dependencies --------------------
info "Checking dynamic dependencies..."

NON_SYSTEM_DEPS=$(otool -L "${BUNDLE_DIR}/xorriso" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -vE "^/usr/lib/|^/System/" || true)

if [ -n "$NON_SYSTEM_DEPS" ]; then
    warn "Unexpected non-system dependencies found:"
    echo "$NON_SYSTEM_DEPS"
    warn "xorriso may not work standalone. Check Homebrew build configuration."
else
    info "No external references. Binary is self-contained!"
fi

# ---------- Step 4: ad-hoc code sign -----------------------------------------
info "Ad-hoc code signing..."
codesign --force -s - "${BUNDLE_DIR}/xorriso" 2>/dev/null || true

# ---------- Step 5: verify ---------------------------------------------------
info "Verifying bundle..."

OUTPUT=$("${BUNDLE_DIR}/xorriso" --version 2>&1 || true)
if echo "$OUTPUT" | grep -qi "xorriso"; then
    info "xorriso --version: OK"
else
    warn "xorriso --version: unexpected output"
fi

info "Final dynamic dependencies:"
otool -L "${BUNDLE_DIR}/xorriso" 2>/dev/null | tail -n +2

# ---------- Step 6: generate bundle file list --------------------------------
info "Generating bundle file list..."

FILE_LIST="${SCRIPT_DIR}/xorriso-bundle-files.txt"
: > "$FILE_LIST"

for file in "${BUNDLE_DIR}"/*; do
    [ -f "$file" ] || continue
    basename "$file" >> "$FILE_LIST"
done

info "File list written to: ${FILE_LIST}"

# ---------- Done -------------------------------------------------------------
info ""
info "=== Bundle complete! ==="
info ""
info "Bundle contents:"
ls -lh "${BUNDLE_DIR}/"
info ""
info "Next steps:"
info "  1. Build in Xcode to verify integration"
