#!/usr/bin/env bash
#
# bundle-cdrtools.sh — Bundle mkisofs from Homebrew for BurnMan
#
# mkisofs (from cdrtools) has no Homebrew dylib dependencies (only /usr/lib/*),
# so we just copy the binary and ad-hoc sign it.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_DIR="${PROJECT_DIR}/BurnMan/Resources/cdrtools-bundle"

# ---------- colours ----------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# ---------- Step 1: locate mkisofs -------------------------------------------
MKISOFS_PATH="$(which mkisofs 2>/dev/null || true)"

if [ -z "$MKISOFS_PATH" ]; then
    error "mkisofs not found. Install it with: brew install cdrtools"
fi

info "Found mkisofs at: ${MKISOFS_PATH}"

# ---------- Step 2: copy binary ----------------------------------------------
info "Copying mkisofs into bundle..."
mkdir -p "$BUNDLE_DIR"
cp "$MKISOFS_PATH" "${BUNDLE_DIR}/mkisofs"
chmod +x "${BUNDLE_DIR}/mkisofs"

# ---------- Step 3: verify no Homebrew dylib dependencies --------------------
info "Checking dynamic dependencies..."

NON_SYSTEM_DEPS=$(otool -L "${BUNDLE_DIR}/mkisofs" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -vE "^/usr/lib/|^/System/" || true)

if [ -n "$NON_SYSTEM_DEPS" ]; then
    warn "Unexpected non-system dependencies found:"
    echo "$NON_SYSTEM_DEPS"
    warn "mkisofs may not work standalone. Check Homebrew build configuration."
else
    info "No external references. Binary is self-contained!"
fi

# ---------- Step 4: ad-hoc code sign -----------------------------------------
info "Ad-hoc code signing..."
codesign --force -s - "${BUNDLE_DIR}/mkisofs" 2>/dev/null || true

# ---------- Step 5: verify ---------------------------------------------------
info "Verifying bundle..."

OUTPUT=$("${BUNDLE_DIR}/mkisofs" --version 2>&1 || true)
if echo "$OUTPUT" | grep -qi "mkisofs\|genisoimage\|cdrtools"; then
    info "mkisofs --version: OK"
else
    warn "mkisofs --version: unexpected output"
fi

info "Final dynamic dependencies:"
otool -L "${BUNDLE_DIR}/mkisofs" 2>/dev/null | tail -n +2

# ---------- Step 6: generate bundle file list --------------------------------
info "Generating bundle file list..."

FILE_LIST="${SCRIPT_DIR}/cdrtools-bundle-files.txt"
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
