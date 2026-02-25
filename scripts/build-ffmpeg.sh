#!/usr/bin/env bash
#
# build-ffmpeg.sh — Build ffmpeg 8.0.1 with full codec support for BurnMan
#
# Produces a self-contained bundle in BurnMan/Resources/ffmpeg-bundle/
# with all dylibs rewritten to @loader_path/ for portability.
#
set -euo pipefail

FFMPEG_VERSION="8.0.1"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/.ffmpeg-build"
BUNDLE_DIR="${PROJECT_DIR}/BurnMan/Resources/ffmpeg-bundle"

HOMEBREW_PREFIX="$(brew --prefix)"

# ---------- helpers ----------------------------------------------------------
# macOS readlink doesn't support -f; use python as fallback
realpath_portable() {
    python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1"
}

# ---------- colours ----------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# ---------- Step 1: install Homebrew dependencies ----------------------------
info "Installing Homebrew dependencies..."

BREW_DEPS=(
    # Build tools
    pkg-config
    # DVD / Blu-ray
    libdvdnav libdvdread libdvdcss libbluray
    # Video codecs (new)
    aom openh264 rav1e theora webp
    # Audio codecs (new)
    fdk-aac libvorbis speex libsoxr
    # Subtitles
    libass freetype fribidi harfbuzz
    # Image / container
    openjpeg librsvg libxml2 zimg snappy
    # Already installed but ensure present
    x264 x265 svt-av1 dav1d libvpx lame opus openssl@3 sdl2
)

brew install "${BREW_DEPS[@]}" 2>&1 | tail -5
info "Homebrew dependencies ready."

# ---------- Step 2: download & extract sources --------------------------------
info "Preparing build directory..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
    if [ ! -f "ffmpeg-${FFMPEG_VERSION}.tar.xz" ]; then
        info "Downloading ffmpeg ${FFMPEG_VERSION}..."
        curl -L -o "ffmpeg-${FFMPEG_VERSION}.tar.xz" "$FFMPEG_URL"
    fi
    info "Extracting..."
    tar xf "ffmpeg-${FFMPEG_VERSION}.tar.xz"
fi

cd "ffmpeg-${FFMPEG_VERSION}"

# Patch: fix svt-av1 >= 4.0 API incompatibility (removed enable_adaptive_quantization)
if grep -q 'enable_adaptive_quantization' libavcodec/libsvtav1.c 2>/dev/null; then
    info "Patching libsvtav1.c for svt-av1 4.x compatibility..."
    sed -i '' '/enable_adaptive_quantization/d' libavcodec/libsvtav1.c
fi

# ---------- Step 3: configure -------------------------------------------------
info "Configuring ffmpeg..."

# Gather pkg-config paths for all Homebrew dependencies
PKG_CONFIG_PATH=""
for dep in "${BREW_DEPS[@]}"; do
    dep_prefix="$(brew --prefix "$dep" 2>/dev/null || true)"
    if [ -n "$dep_prefix" ] && [ -d "$dep_prefix/lib/pkgconfig" ]; then
        PKG_CONFIG_PATH="${dep_prefix}/lib/pkgconfig:${PKG_CONFIG_PATH}"
    fi
done
export PKG_CONFIG_PATH

# Extra CFLAGS/LDFLAGS for deps without pkg-config or in non-standard locations
EXTRA_CFLAGS="-I${HOMEBREW_PREFIX}/include"
EXTRA_LDFLAGS="-L${HOMEBREW_PREFIX}/lib"

# Add specific prefixes for keg-only formulas
for keg_dep in openssl@3 libxml2; do
    keg_prefix="$(brew --prefix "$keg_dep" 2>/dev/null || true)"
    if [ -n "$keg_prefix" ]; then
        EXTRA_CFLAGS="${EXTRA_CFLAGS} -I${keg_prefix}/include"
        EXTRA_LDFLAGS="${EXTRA_LDFLAGS} -L${keg_prefix}/lib"
    fi
done

./configure \
    --prefix="${BUILD_DIR}/install" \
    --enable-shared \
    --disable-static \
    --enable-gpl \
    --enable-version3 \
    --enable-nonfree \
    --enable-pthreads \
    \
    --enable-ffplay \
    \
    --extra-cflags="${EXTRA_CFLAGS}" \
    --extra-ldflags="${EXTRA_LDFLAGS}" \
    \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libsvtav1 \
    --enable-libdav1d \
    --enable-libvpx \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-openssl \
    \
    --enable-videotoolbox \
    --enable-audiotoolbox \
    --enable-neon \
    --enable-opencl \
    \
    --enable-libdvdnav \
    --enable-libdvdread \
    --enable-libbluray \
    \
    --enable-libaom \
    --enable-libopenh264 \
    --enable-librav1e \
    --enable-libtheora \
    --enable-libwebp \
    \
    --enable-libfdk-aac \
    --enable-libvorbis \
    --enable-libspeex \
    --enable-libsoxr \
    \
    --enable-libass \
    --enable-libfreetype \
    --enable-libfribidi \
    --enable-libharfbuzz \
    \
    --enable-libopenjpeg \
    --enable-librsvg \
    --enable-libxml2 \
    --enable-libzimg \
    --enable-libsnappy

info "Configuration complete."

# ---------- Step 4: compile ---------------------------------------------------
NCPU=$(sysctl -n hw.ncpu)
info "Building with ${NCPU} threads..."
make -j"${NCPU}"
make install

info "Build complete."

# ---------- Step 5 & 6: collect binaries + dylibs ----------------------------
info "Collecting binaries and libraries into bundle..."

# Clean old bundle (keep directory)
rm -rf "${BUNDLE_DIR:?}"/*

# Libs provided by cdrdao-bundle — skip to avoid duplicate copy conflicts in Xcode
CDRDAO_PROVIDED=("libvorbis.0" "libogg.0" "libvorbisfile.3")

# Copy ffmpeg binaries
for bin in ffmpeg ffprobe ffplay; do
    cp "${BUILD_DIR}/install/bin/${bin}" "${BUNDLE_DIR}/"
    chmod +x "${BUNDLE_DIR}/${bin}"
done

# Copy our own built dylibs (libav*, libsw*)
# Copy both the real file and the short-name symlink target
for dylib in "${BUILD_DIR}"/install/lib/lib*.dylib; do
    real=$(realpath_portable "$dylib")
    basename_real=$(basename "$real")
    # Skip if already copied
    [ -f "${BUNDLE_DIR}/${basename_real}" ] && continue
    cp "$real" "${BUNDLE_DIR}/"
done

# Also create short-name copies (e.g., libavcodec.62.dylib -> libavcodec.62.11.100.dylib)
for symlink in "${BUILD_DIR}"/install/lib/lib*.dylib; do
    [ -L "$symlink" ] || continue
    link_base=$(basename "$symlink")
    # Match pattern like libfoo.NN.dylib (major version only)
    if [[ "$link_base" =~ ^lib[a-z]+\.[0-9]+\.dylib$ ]]; then
        target=$(readlink "$symlink")
        target_base=$(basename "$target")
        if [ -f "${BUNDLE_DIR}/${target_base}" ] && [ ! -f "${BUNDLE_DIR}/${link_base}" ]; then
            cp "${BUNDLE_DIR}/${target_base}" "${BUNDLE_DIR}/${link_base}"
        fi
    fi
done

# Resolve and copy all Homebrew dylib dependencies recursively
collect_deps() {
    local binary="$1"
    otool -L "$binary" 2>/dev/null | awk '{print $1}' | while read -r dep; do
        # Collect Homebrew libs and @rpath libs
        case "$dep" in
            ${HOMEBREW_PREFIX}/*)
                local dep_real
                dep_real=$(realpath_portable "$dep")
                local dep_base
                dep_base=$(basename "$dep_real")
                if [ ! -f "${BUNDLE_DIR}/${dep_base}" ] && [ -f "$dep_real" ]; then
                    cp "$dep_real" "${BUNDLE_DIR}/"
                    info "  Collected: ${dep_base}"
                    collect_deps "$dep_real"
                fi
                # Also copy the versioned symlink name if different
                local dep_link_base
                dep_link_base=$(basename "$dep")
                if [ "$dep_link_base" != "$dep_base" ] && [ ! -f "${BUNDLE_DIR}/${dep_link_base}" ]; then
                    cp "$dep_real" "${BUNDLE_DIR}/${dep_link_base}"
                fi
                ;;
            @rpath/*)
                # Some Homebrew libs use @rpath internally (e.g., libwebp -> libsharpyuv)
                local rpath_name
                rpath_name=$(basename "$dep")
                if [ ! -f "${BUNDLE_DIR}/${rpath_name}" ]; then
                    # Search for it in Homebrew
                    local found
                    found=$(find "${HOMEBREW_PREFIX}/lib" -name "${rpath_name}" -type f 2>/dev/null | head -1)
                    if [ -n "$found" ]; then
                        cp "$found" "${BUNDLE_DIR}/"
                        info "  Collected (@rpath): ${rpath_name}"
                        collect_deps "$found"
                    fi
                fi
                ;;
        esac
    done
}

info "Collecting Homebrew dependencies..."
for file in "${BUNDLE_DIR}"/*; do
    [ -f "$file" ] && collect_deps "$file"
done

# Additional passes to catch transitive deps
for pass in 2 3; do
    info "Pass ${pass} for transitive dependencies..."
    for file in "${BUNDLE_DIR}"/*; do
        [ -f "$file" ] && collect_deps "$file"
    done
done

# Create short-name copies for Homebrew libs with full version numbers
# e.g., libfoo.N.N.N.dylib -> libfoo.N.dylib
info "Creating short-name symlinks..."
for file in "${BUNDLE_DIR}"/*.dylib; do
    [ -f "$file" ] || continue
    base=$(basename "$file")
    if [[ "$base" =~ ^(lib[^.]+\.[0-9]+)\.[0-9]+.*\.dylib$ ]]; then
        short="${BASH_REMATCH[1]}.dylib"
        if [ ! -f "${BUNDLE_DIR}/${short}" ]; then
            cp "$file" "${BUNDLE_DIR}/${short}"
            info "  ${short}"
        fi
    fi
done

# Remove libs already provided by cdrdao-bundle to avoid Xcode duplicate copy errors
info "Removing libs provided by cdrdao-bundle..."
for prefix in "${CDRDAO_PROVIDED[@]}"; do
    for dup in "${BUNDLE_DIR}/${prefix}"*.dylib; do
        [ -f "$dup" ] || continue
        info "  Removing: $(basename "$dup") (provided by cdrdao-bundle)"
        rm "$dup"
    done
done

info "Collected $(ls "${BUNDLE_DIR}" | wc -l | tr -d ' ') files total."

# ---------- Step 7: rewrite install names ------------------------------------
info "Rewriting dylib install names to @loader_path/..."

for file in "${BUNDLE_DIR}"/*; do
    [ -f "$file" ] || continue

    # Change the library's own ID
    basename_file=$(basename "$file")
    current_id=$(otool -D "$file" 2>/dev/null | tail -1)
    if [ -n "$current_id" ] && [ "$current_id" != "@loader_path/${basename_file}" ]; then
        install_name_tool -id "@loader_path/${basename_file}" "$file" 2>/dev/null || true
    fi

    # Rewrite all dependency paths (absolute and @rpath)
    otool -L "$file" 2>/dev/null | awk '{print $1}' | while read -r dep; do
        dep_base=$(basename "$dep")
        case "$dep" in
            ${HOMEBREW_PREFIX}/*|${BUILD_DIR}/*|/usr/local/*)
                if [ -f "${BUNDLE_DIR}/${dep_base}" ]; then
                    install_name_tool -change "$dep" "@loader_path/${dep_base}" "$file" 2>/dev/null || true
                fi
                ;;
            @rpath/*)
                if [ -f "${BUNDLE_DIR}/${dep_base}" ]; then
                    install_name_tool -change "$dep" "@loader_path/${dep_base}" "$file" 2>/dev/null || true
                fi
                ;;
        esac
    done
done

# ---------- Step 8: ad-hoc code sign -----------------------------------------
# install_name_tool invalidates code signatures; re-sign everything
info "Ad-hoc code signing all files..."
for file in "${BUNDLE_DIR}"/*; do
    [ -f "$file" ] || continue
    codesign --force -s - "$file" 2>/dev/null || true
done

# ---------- Step 9: verify ---------------------------------------------------
info "Verifying bundle..."

ERRORS=0
for file in "${BUNDLE_DIR}"/*; do
    [ -f "$file" ] || continue
    # Skip first line (file path itself), check only dependency lines
    bad_refs=$(otool -L "$file" 2>/dev/null | tail -n +2 | grep -cE "@rpath/|${HOMEBREW_PREFIX}/|${BUILD_DIR}/" || true)
    if [ "$bad_refs" -gt 0 ]; then
        warn "$(basename "$file") still has ${bad_refs} absolute/rpath reference(s):"
        otool -L "$file" | tail -n +2 | grep -E "@rpath/|${HOMEBREW_PREFIX}/|${BUILD_DIR}/"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ "$ERRORS" -eq 0 ]; then
    info "No absolute/rpath references found. Bundle is self-contained!"
else
    error "${ERRORS} file(s) still have unresolved references."
fi

# Functional checks
info "Checking DVD/Blu-ray support..."
"${BUNDLE_DIR}/ffmpeg" -hide_banner -demuxers 2>/dev/null | grep -q "dvdvideo" \
    && info "  dvdvideo demuxer: FOUND" \
    || warn "  dvdvideo demuxer: NOT FOUND"

"${BUNDLE_DIR}/ffmpeg" -hide_banner -protocols 2>/dev/null | grep -q "bluray" \
    && info "  bluray protocol: FOUND" \
    || warn "  bluray protocol: NOT FOUND"

ENC_COUNT=$("${BUNDLE_DIR}/ffmpeg" -hide_banner -encoders 2>/dev/null | grep -c "^ " || echo 0)
DEC_COUNT=$("${BUNDLE_DIR}/ffmpeg" -hide_banner -decoders 2>/dev/null | grep -c "^ " || echo 0)
info "  Encoders: ${ENC_COUNT}"
info "  Decoders: ${DEC_COUNT}"

[ -f "${BUNDLE_DIR}/libdvdcss.2.dylib" ] \
    && info "  libdvdcss: BUNDLED" \
    || warn "  libdvdcss: NOT FOUND in bundle"

# ---------- Step 10: generate pbxproj dylib list -----------------------------
info "Generating dylib list for Xcode project..."

DYLIB_LIST_FILE="${SCRIPT_DIR}/ffmpeg-bundle-dylibs.txt"
: > "$DYLIB_LIST_FILE"

for file in "${BUNDLE_DIR}"/*.dylib; do
    [ -f "$file" ] || continue
    basename "$file" >> "$DYLIB_LIST_FILE"
done

info "Dylib list written to: ${DYLIB_LIST_FILE}"
info ""
info "=== Build complete! ==="
info ""
info "Next steps:"
info "  1. Review the dylib list: cat ${DYLIB_LIST_FILE}"
info "  2. Update BurnMan.xcodeproj/project.pbxproj with new dylibs"
info "  3. Build in Xcode to verify"
