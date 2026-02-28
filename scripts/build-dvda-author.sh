#!/usr/bin/env bash
#
# build-dvda-author.sh — Build dvda-author from source for BurnMan
#
# Produces a self-contained binary in BurnMan/Resources/dvda-author-bundle/
# The binary is statically linked against its dependencies (no external dylibs).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/.dvda-author-build"
BUNDLE_DIR="${PROJECT_DIR}/BurnMan/Resources/dvda-author-bundle"

DVDA_REPO="https://github.com/fabnicol/dvda-author.git"

# ---------- colours ----------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; exit 1; }

# ---------- Step 1: install Homebrew dependencies ----------------------------
info "Installing Homebrew dependencies..."

BREW_DEPS=(
    autoconf automake libtool pkg-config gcc
    flac libogg
    make
)

brew install "${BREW_DEPS[@]}" 2>&1 | tail -5
info "Homebrew dependencies ready."

# dvda-author requires GNU make >= 3.82 (.ONESHELL support).
# macOS ships 3.81; Homebrew installs 4.x as "gmake".
# Create a symlink so configure finds it as "make".
if command -v gmake &>/dev/null; then
    mkdir -p "${BUILD_DIR}/bin"
    ln -sf "$(which gmake)" "${BUILD_DIR}/bin/make"
    export PATH="${BUILD_DIR}/bin:$PATH"
    info "Using GNU make $(gmake --version | head -1)"
fi

# NOTE: dvda-author uses ffmpeg 4.x API (c->channels, c->channel_layout)
# which was removed in ffmpeg 5.1+. We compile the vendored ffmpeg 4.2.4
# from the dvda-author repo (not our bundled ffmpeg 8.0.1).

# ---------- Step 3: clone the repo -------------------------------------------
info "Preparing build directory..."
mkdir -p "$BUILD_DIR"

if [ ! -d "${BUILD_DIR}/dvda-author" ]; then
    info "Cloning dvda-author..."
    git clone "$DVDA_REPO" "${BUILD_DIR}/dvda-author"
else
    info "dvda-author source already present, pulling latest..."
    git -C "${BUILD_DIR}/dvda-author" pull --ff-only || true
fi

cd "${BUILD_DIR}/dvda-author"

# ---------- Step 4: detect GCC -----------------------------------------------
GCC_PREFIX="$(brew --prefix gcc)"
GCC_VERSION=$(ls "${GCC_PREFIX}/bin/" | grep -oE 'gcc-[0-9]+' | head -1 | sed 's/gcc-//')
if [ -z "$GCC_VERSION" ]; then
    error "Could not detect GCC version in ${GCC_PREFIX}/bin/"
fi

# ---------- Step 5: generate build system ------------------------------------
info "Running autogen..."

# macOS fixes for the autogen script:
# 1. libtoolize is called glibtoolize on macOS
# 2. sed -r (GNU) must be sed -E (BSD/macOS)
# 3. Missing automake auxiliary files (install-sh, config.guess, config.sub)

# Create a libtoolize symlink if needed
if ! command -v libtoolize &>/dev/null && command -v glibtoolize &>/dev/null; then
    info "Creating libtoolize → glibtoolize symlink..."
    mkdir -p "${BUILD_DIR}/bin"
    ln -sf "$(which glibtoolize)" "${BUILD_DIR}/bin/libtoolize"
    export PATH="${BUILD_DIR}/bin:$PATH"
fi

# The autogen script is fragile on macOS. We run our own autotools sequence:
# 1. libtoolize to install libtool macros
# 2. aclocal to collect all m4 macros (including libtool's LT_INIT)
# 3. autoconf to generate configure
# 4. autoheader for config.h.in

info "Running libtoolize..."
libtoolize --force --copy --install 2>/dev/null || true

info "Running aclocal..."
aclocal -I m4 -I m4.extra -I m4.extra.dvdauthor 2>/dev/null || aclocal -I m4

info "Running autoconf..."
autoconf -f -Im4 -Im4.extra -Im4.extra.dvdauthor --warnings=none 2>/dev/null || autoconf -f -Im4 --warnings=none

info "Running autoheader..."
autoheader --warnings=none 2>/dev/null || true

# Ensure automake auxiliary files are present in config/ (AC_CONFIG_AUX_DIR)
AUX_DIR="config"
mkdir -p "$AUX_DIR"
AUTOMAKE_DIR="$(automake --print-libdir 2>/dev/null || echo /opt/homebrew/share/automake-1.18)"
for aux_file in install-sh config.guess config.sub; do
    if [ ! -f "${AUX_DIR}/${aux_file}" ]; then
        if [ -f "${AUTOMAKE_DIR}/${aux_file}" ]; then
            cp "${AUTOMAKE_DIR}/${aux_file}" "${AUX_DIR}/"
            info "  Copied ${aux_file} into ${AUX_DIR}/"
        fi
    fi
done

if [ ! -f "configure" ]; then
    error "configure script not generated"
fi

# ---------- Step 6: configure ------------------------------------------------
info "Configuring dvda-author..."

# GCC_PREFIX and GCC_VERSION already set in Step 4b
info "Using GCC ${GCC_VERSION} from ${GCC_PREFIX}"

# Build configure flags
# MAKE_PATH: configure uses AC_PATH_PROG with hardcoded search dirs;
# pre-set it so it finds GNU make 4.x instead of macOS make 3.81
GMAKE_PATH="$(which gmake 2>/dev/null || which make)"
CONFIGURE_FLAGS=(
    CC="${GCC_PREFIX}/bin/gcc-${GCC_VERSION}"
    CXX="${GCC_PREFIX}/bin/g++-${GCC_VERSION}"
    AR="${GCC_PREFIX}/bin/gcc-ar-${GCC_VERSION}"
    MAKE_PATH="${GMAKE_PATH}"
    --prefix="${BUILD_DIR}/install"
    --without-sox
)

# Try to enable audio features; skip ffmpeg vendored build (we use our own)
# Check what configure flags are available
AVAILABLE_FLAGS=$(./configure --help 2>/dev/null || true)

add_flag_if_available() {
    local flag="$1"
    if echo "$AVAILABLE_FLAGS" | grep -q -- "$flag"; then
        CONFIGURE_FLAGS+=("$flag")
        info "  Enabling: $flag"
    else
        warn "  Not available: $flag"
    fi
}

info "Checking available configure flags..."
add_flag_if_available "--enable-flac-build"
add_flag_if_available "--enable-libogg-build"
# sox is NOT enabled: dvda-author's libsoxconvert.c uses old sox API types
# incompatible with modern sox. Sox is optional (format conversion only).
add_flag_if_available "--enable-a52dec-build"
add_flag_if_available "--enable-libmpeg2-build"

./configure "${CONFIGURE_FLAGS[@]}"

info "Configuration complete."

# ---------- Step 6b: build vendored ffmpeg 4.2.4 into local/ -----------------
# IMPORTANT: This must run AFTER dvda-author's configure, because configure
# does `rm -rf local && mkdir local` — wiping anything we put there earlier.
#
# dvda-author uses the ffmpeg 4.x API (c->channels, c->channel_layout,
# av_init_packet) which was removed in ffmpeg 5.1+.
# The repo ships ffmpeg-4.2.4/ source; build it with a minimal config
# (MLP codec + PCM + WAV, matching m4/dependencies.m4 flags).
info "Building vendored ffmpeg 4.2.4 (minimal MLP config)..."

if [ -f "local/lib/libavcodec.a" ] && [ -f "local/include/libavcodec/avcodec.h" ]; then
    info "Vendored ffmpeg already built (local/lib/libavcodec.a exists), skipping."
else
    if [ ! -d "ffmpeg-4.2.4" ]; then
        error "ffmpeg-4.2.4/ directory not found in dvda-author repo"
    fi

    cd ffmpeg-4.2.4
    # Ensure all scripts are executable (git may strip +x bits)
    chmod +x configure ffbuild/*.sh version.sh 2>/dev/null || true
    find . -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

    # Clean any previous partial build
    make distclean 2>/dev/null || true

    ./configure \
        --prefix="${BUILD_DIR}/dvda-author/local" \
        --cc="${GCC_PREFIX}/bin/gcc-${GCC_VERSION}" \
        --disable-demuxers --disable-decoders --disable-muxers --disable-parsers \
        --disable-encoders --disable-devices --disable-protocols \
        --enable-protocol=file --enable-protocol=data \
        --disable-bsfs --disable-hwaccels --disable-filters \
        --enable-decoder=mlp --enable-encoder=mlp \
        --enable-encoder=pcm_s16le --enable-encoder=pcm_s24le --enable-encoder=pcm_s32le \
        --enable-decoder=pcm_s16le --enable-decoder=pcm_s24le \
        --enable-parser=mlp \
        --enable-muxer=wav --enable-muxer=null --enable-muxer=truehd --enable-muxer=mlp \
        --enable-muxer=pcm_s16le --enable-muxer=pcm_s24le --enable-muxer=pcm_s32le \
        --enable-demuxer=mlp --enable-demuxer=pcm_s16le --enable-demuxer=pcm_s24le \
        --enable-demuxer=pcm_s32le --enable-demuxer=wav --enable-demuxer=truehd \
        --enable-filter=aresample \
        --disable-bzlib --disable-iconv --disable-libxcb --disable-libxcb-shm \
        --disable-libxcb-xfixes --disable-libxcb-shape --disable-sndio --disable-sdl2 \
        --disable-zlib --disable-xlib --disable-libdrm --disable-vaapi --disable-vdpau \
        --disable-videotoolbox \
        --enable-static --disable-shared \
        --disable-swscale --disable-network --disable-postproc --disable-pixelutils \
        --disable-avdevice --disable-alsa --disable-lzma --disable-doc \
        --disable-x86asm \
        --enable-pic

    make -j$(sysctl -n hw.ncpu)
    make install
    cd ..

    # Verify ffmpeg build produced the required files
    if [ ! -f "local/lib/libavcodec.a" ]; then
        error "ffmpeg build failed: local/lib/libavcodec.a not found"
    fi
    if [ ! -f "local/include/libavcodec/avcodec.h" ]; then
        error "ffmpeg build failed: local/include/libavcodec/avcodec.h not found"
    fi
    info "Vendored ffmpeg 4.2.4 build complete."
fi

info "Vendored libraries in local/lib/:"
ls local/lib/*.a 2>/dev/null | head -10 || warn "No .a files found in local/lib/"

# ---------- Step 7: patch & compile ------------------------------------------
NCPU=$(sysctl -n hw.ncpu)
info "Applying macOS compatibility patches..."

# Fix 1: clean_exit() called with 1 arg instead of 2 (source bug)
sed -i '' 's/clean_exit(-1);/clean_exit(-1, NULL);/' libutils/src/libc_utils.c 2>/dev/null || true

# Fix 2: .ONESHELL causes fork-bomb on macOS (cd in separate shell → infinite recursion)
sed -i '' 's/^\.ONESHELL:/#.ONESHELL:/' Makefile
sed -i '' 's/^\.SHELLFLAGS=/#.SHELLFLAGS=/' Makefile
# Replace the libfixwav recipe: cd libfixwav/src + $(MAKE) → $(MAKE) -C libfixwav/src
if grep -q 'cd libfixwav/src' Makefile; then
    sed -i '' '/^libfixwav:/,/^[^ \t]/ {
        s|cd libfixwav/src|# cd libfixwav/src|
        s|	$(MAKE)$|	$(MAKE) -C libfixwav/src|
        s|cd -|# cd -|
    }' Makefile
fi

# Set up compiler
CC_FOR_BUILD="${GCC_PREFIX}/bin/gcc-${GCC_VERSION}"
CXX_FOR_BUILD="${GCC_PREFIX}/bin/g++-${GCC_VERSION}"
AR_FOR_BUILD="${GCC_PREFIX}/bin/gcc-ar-${GCC_VERSION}"

info "Building with ${NCPU} threads..."
info "  CC=${CC_FOR_BUILD}"

# Build core components directly (the top-level Makefile has .ONESHELL issues)
# GCC 15 defaults to C23 where () means void — the old code uses C89 () for unspecified args.
# Use gnu99 to match the project's expected C standard.
# Don't pass CPPFLAGS on command line — it overrides the sub-Makefiles' CPPFLAGS +=
# GCC 15 is stricter than what this old codebase was written for.
# Suppress type-related warnings-as-errors while keeping the core build functional.
BUILD_CFLAGS="-g -O2 -std=gnu99 -DHAVE_CONFIG_H -Wno-incompatible-pointer-types -Wno-implicit-function-declaration -Wno-int-conversion"

info "Building libfixwav..."
make -C libfixwav/src CC="${CC_FOR_BUILD}" CFLAGS="${BUILD_CFLAGS}" 2>&1

info "Building libutils..."
make -C libutils/src CC="${CC_FOR_BUILD}" CFLAGS="${BUILD_CFLAGS}" 2>&1

info "Building dvda-author..."
make -C src CC="${CC_FOR_BUILD}" CXX="${CXX_FOR_BUILD}" AR="${AR_FOR_BUILD}" \
    CFLAGS="${BUILD_CFLAGS}" 2>&1

info "Build complete."

# ---------- Step 8: collect the binary ---------------------------------------
info "Collecting binary into bundle..."

mkdir -p "$BUNDLE_DIR"

# The binary may be named dvda-author-dev or dvda-author
BINARY=""
for candidate in src/dvda-author-dev src/dvda-author dvda-author-dev dvda-author; do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
        BINARY="$candidate"
        break
    fi
done

if [ -z "$BINARY" ]; then
    # Search more broadly
    BINARY=$(find . -name "dvda-author*" -type f -perm +111 ! -name "*.o" ! -name "*.sh" | head -1)
fi

if [ -z "$BINARY" ]; then
    error "Could not find dvda-author binary after build"
fi

info "Found binary: ${BINARY}"
cp "$BINARY" "${BUNDLE_DIR}/dvda-author"
chmod +x "${BUNDLE_DIR}/dvda-author"

# ---------- Step 9: check dynamic dependencies & collect if needed -----------
info "Checking dynamic dependencies..."

HOMEBREW_PREFIX="$(brew --prefix)"

# Check for non-system dylibs
NON_SYSTEM_DEPS=$(otool -L "${BUNDLE_DIR}/dvda-author" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -vE "^/usr/lib/|^/System/" || true)

if [ -n "$NON_SYSTEM_DEPS" ]; then
    warn "Non-system dynamic dependencies found:"
    echo "$NON_SYSTEM_DEPS"

    # Collect any Homebrew dylibs that aren't already in other bundles
    FFMPEG_BUNDLE="${PROJECT_DIR}/BurnMan/Resources/ffmpeg-bundle"
    CDRDAO_BUNDLE="${PROJECT_DIR}/BurnMan/Resources/cdrdao-bundle"

    for dep in $NON_SYSTEM_DEPS; do
        dep_base=$(basename "$dep")

        # Skip if already in another bundle (they'll be in Frameworks/ at runtime)
        if [ -f "${FFMPEG_BUNDLE}/${dep_base}" ] || [ -f "${CDRDAO_BUNDLE}/${dep_base}" ]; then
            info "  ${dep_base}: already in another bundle, skipping"
            continue
        fi

        # If it's a Homebrew lib, copy and rewrite
        case "$dep" in
            ${HOMEBREW_PREFIX}/*|/usr/local/*)
                if [ -f "$dep" ]; then
                    cp "$dep" "${BUNDLE_DIR}/"
                    install_name_tool -change "$dep" "@loader_path/${dep_base}" "${BUNDLE_DIR}/dvda-author" 2>/dev/null || true
                    info "  Collected: ${dep_base}"
                fi
                ;;
            @rpath/*|@loader_path/*)
                # Already relative, should be fine
                ;;
            *)
                warn "  Unknown dep: ${dep}"
                ;;
        esac
    done

    # Rewrite install names on any collected dylibs
    for dylib in "${BUNDLE_DIR}"/*.dylib; do
        [ -f "$dylib" ] || continue
        basename_dylib=$(basename "$dylib")
        install_name_tool -id "@loader_path/${basename_dylib}" "$dylib" 2>/dev/null || true

        otool -L "$dylib" 2>/dev/null | awk '{print $1}' | while read -r dep; do
            dep_base=$(basename "$dep")
            case "$dep" in
                ${HOMEBREW_PREFIX}/*|/usr/local/*)
                    if [ -f "${BUNDLE_DIR}/${dep_base}" ]; then
                        install_name_tool -change "$dep" "@loader_path/${dep_base}" "$dylib" 2>/dev/null || true
                    fi
                    ;;
            esac
        done
    done
else
    info "Binary is fully statically linked (only system libs). No dylibs to collect."
fi

# ---------- Step 10: ad-hoc code sign ----------------------------------------
info "Ad-hoc code signing..."
for file in "${BUNDLE_DIR}"/*; do
    [ -f "$file" ] || continue
    codesign --force -s - "$file" 2>/dev/null || true
done

# ---------- Step 11: verify --------------------------------------------------
info "Verifying bundle..."

# Check the binary runs
if "${BUNDLE_DIR}/dvda-author" --help >/dev/null 2>&1; then
    info "dvda-author --help: OK"
else
    # Some tools return non-zero for --help; check if it at least outputs something
    OUTPUT=$("${BUNDLE_DIR}/dvda-author" --help 2>&1 || true)
    if [ -n "$OUTPUT" ]; then
        info "dvda-author --help: OK (non-zero exit but produced output)"
    else
        warn "dvda-author --help: produced no output"
    fi
fi

# Check for external references
EXTERNAL_REFS=$(otool -L "${BUNDLE_DIR}/dvda-author" 2>/dev/null | tail -n +2 | grep -vE "^\\s*/usr/lib/|^\\s*/System/|^\\s*@loader_path/" || true)
if [ -n "$EXTERNAL_REFS" ]; then
    warn "External references remaining:"
    echo "$EXTERNAL_REFS"
else
    info "No external references found. Binary is self-contained!"
fi

# Show final dependency list
info "Final dynamic dependencies:"
otool -L "${BUNDLE_DIR}/dvda-author" 2>/dev/null | tail -n +2

# ---------- Step 12: generate bundle file list --------------------------------
info "Generating bundle file list..."

FILE_LIST="${SCRIPT_DIR}/dvda-author-bundle-files.txt"
: > "$FILE_LIST"

for file in "${BUNDLE_DIR}"/*; do
    [ -f "$file" ] || continue
    basename "$file" >> "$FILE_LIST"
done

info "File list written to: ${FILE_LIST}"

# ---------- Done -------------------------------------------------------------
info ""
info "=== Build complete! ==="
info ""
info "Bundle contents:"
ls -lh "${BUNDLE_DIR}/"
info ""
info "Next steps:"
info "  1. Review the file list: cat ${FILE_LIST}"
info "  2. Build in Xcode to verify integration"
