#!/usr/bin/env bash
# build-mpv-macos.sh — Builds mpv as LGPL (libmpv) for Flux
# Output: Dependencies/mpv/{lib,include}
#
# LGPL compliance: built with -Dgpl=false.
# Lost features in LGPL mode (irrelevant on macOS):
#   - X11/Wayland video output (Linux only)
#   - OSS audio (Linux/BSD only)
#   - vdpau (Linux NVIDIA only)
#   - yadif deinterlace filter (rarely used on modern content)
#   - DVD/CDDA/DVB support
# All macOS-relevant features (VideoToolbox, Metal, libass, libplacebo) are retained.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/Dependencies/mpv"
BUILD_DIR="$REPO_ROOT/Dependencies/build/mpv"
FFMPEG_DIR="$REPO_ROOT/Dependencies/ffmpeg"
MPV_VERSION="0.39.0"
MPV_URL="https://github.com/mpv-player/mpv/archive/refs/tags/v${MPV_VERSION}.tar.gz"

MACOS_MIN="12.0"
ARCHS=("arm64" "x86_64")

echo "==> Building mpv ${MPV_VERSION} (LGPL) for macOS"
echo "    Output: $OUTPUT_DIR"

# Verify FFmpeg was built first
if [ ! -f "$FFMPEG_DIR/lib/libavcodec.dylib" ]; then
    echo "ERROR: FFmpeg not found at $FFMPEG_DIR"
    echo "Run build-ffmpeg-macos.sh first."
    exit 1
fi

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Set PKG_CONFIG_PATH to include our LGPL FFmpeg
export PKG_CONFIG_PATH="$FFMPEG_DIR/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# Download mpv source
TARBALL="$BUILD_DIR/mpv-${MPV_VERSION}.tar.gz"
if [ ! -f "$TARBALL" ]; then
    echo "==> Downloading mpv ${MPV_VERSION}..."
    curl -L "$MPV_URL" -o "$TARBALL"
fi

SOURCE_DIR="$BUILD_DIR/mpv-${MPV_VERSION}"
if [ ! -d "$SOURCE_DIR" ]; then
    echo "==> Extracting..."
    tar -xf "$TARBALL" -C "$BUILD_DIR"
fi

build_for_arch() {
    local ARCH="$1"
    local INSTALL_DIR="$BUILD_DIR/install-${ARCH}"
    local BUILD_SUBDIR="$BUILD_DIR/build-${ARCH}"
    mkdir -p "$INSTALL_DIR" "$BUILD_SUBDIR"

    echo "==> Configuring mpv for ${ARCH}..."

    # Architecture-specific flags
    if [ "$ARCH" = "arm64" ]; then
        CROSS_ARGS="--cross-file=$SCRIPT_DIR/cross-arm64-macos.ini"
        create_cross_file "arm64" "aarch64"
    else
        CROSS_ARGS="--cross-file=$SCRIPT_DIR/cross-x86_64-macos.ini"
        create_cross_file "x86_64" "x86_64"
    fi

    meson setup "$BUILD_SUBDIR" "$SOURCE_DIR" \
        --prefix="$INSTALL_DIR" \
        --buildtype=release \
        --default-library=shared \
        $CROSS_ARGS \
        \
        -Dgpl=false \
        -Dlibmpv=true \
        \
        `# Video outputs — use libmpv render API, not standalone vo` \
        -Dcocoa=enabled \
        -Dplain-gl=disabled \
        -Dgl=disabled \
        -Dvulkan=disabled \
        -Dwayland=disabled \
        -Dx11=disabled \
        \
        `# Hardware decode` \
        -Dvideotoolbox-gl=disabled \
        \
        `# Audio` \
        -Dcoreaudio=enabled \
        \
        `# Subtitle rendering` \
        -Dlibass=enabled \
        -Dlibass-osd=enabled \
        \
        `# HDR tone-mapping (libplacebo via gpu-next VO)` \
        -Dlibplacebo=enabled \
        \
        `# Disable Linux/Windows-specific outputs` \
        -Ddrm=disabled \
        -Dgbm=disabled \
        -Doss-audio=disabled \
        -Dpulse=disabled \
        -Dalsa=disabled \
        -Djack=disabled \
        -Dpipewire=disabled \
        -Ddvdnav=disabled \
        -Ddvdread=disabled \
        -Dcdda=disabled \
        -Ddvbin=disabled \
        \
        `# Lua scripting (keep — useful for power users)` \
        -Dlua=enabled \
        \
        `# JavaScript scripting` \
        -Djavascript=disabled \
        \
        `# Build tools` \
        -Dbuild-date=false

    echo "==> Building mpv for ${ARCH}..."
    meson compile -C "$BUILD_SUBDIR" -j "$(sysctl -n hw.logicalcpu)"
    meson install -C "$BUILD_SUBDIR"

    echo "==> Done: mpv ${ARCH}"
}

create_cross_file() {
    local ARCH="$1"
    local CPU_FAMILY="$2"
    local CROSS_FILE="$SCRIPT_DIR/cross-${ARCH}-macos.ini"

    cat > "$CROSS_FILE" << EOF
[host_machine]
system = 'darwin'
cpu_family = '${CPU_FAMILY}'
cpu = '${ARCH}'
endian = 'little'

[built-in options]
c_args = ['-arch', '${ARCH}', '-mmacosx-version-min=${MACOS_MIN}']
cpp_args = ['-arch', '${ARCH}', '-mmacosx-version-min=${MACOS_MIN}']
objc_args = ['-arch', '${ARCH}', '-mmacosx-version-min=${MACOS_MIN}']
c_link_args = ['-arch', '${ARCH}', '-mmacosx-version-min=${MACOS_MIN}']
cpp_link_args = ['-arch', '${ARCH}', '-mmacosx-version-min=${MACOS_MIN}']
EOF
}

# Build for each architecture
for ARCH in "${ARCHS[@]}"; do
    build_for_arch "$ARCH"
done

# Create universal binaries
echo "==> Creating universal binaries..."
mkdir -p "$OUTPUT_DIR/lib" "$OUTPUT_DIR/include"

# Copy headers from arm64 build
cp -r "$BUILD_DIR/install-arm64/include/mpv" "$OUTPUT_DIR/include/"

# Lipo libmpv
lipo -create \
    "$BUILD_DIR/install-arm64/lib/libmpv.dylib" \
    "$BUILD_DIR/install-x86_64/lib/libmpv.dylib" \
    -output "$OUTPUT_DIR/lib/libmpv.dylib"

# Fix install name for embedding in app bundle
install_name_tool -id "@rpath/libmpv.dylib" "$OUTPUT_DIR/lib/libmpv.dylib"

# Copy pkgconfig
mkdir -p "$OUTPUT_DIR/lib/pkgconfig"
cp "$BUILD_DIR/install-arm64/lib/pkgconfig/mpv.pc" "$OUTPUT_DIR/lib/pkgconfig/"
sed -i '' "s|prefix=$BUILD_DIR/install-arm64|prefix=$OUTPUT_DIR|g" "$OUTPUT_DIR/lib/pkgconfig/mpv.pc"

echo ""
echo "==> mpv LGPL build complete."
echo "    Library: $OUTPUT_DIR/lib/libmpv.dylib"
echo "    Headers: $OUTPUT_DIR/include/mpv/"
echo ""
echo "==> Verifying LGPL compliance..."
echo "    Linked libraries:"
otool -L "$OUTPUT_DIR/lib/libmpv.dylib"
echo ""
echo "    GPL check (should be empty):"
otool -L "$OUTPUT_DIR/lib/libmpv.dylib" | grep -E "(libx264|libx265|libxvid|yadif)" && echo "WARNING: GPL library found!" || echo "    LGPL verification: OK"
echo ""
echo "==> Set PKG_CONFIG_PATH before opening Xcode:"
echo "    export PKG_CONFIG_PATH=\"$OUTPUT_DIR/lib/pkgconfig:$FFMPEG_DIR/lib/pkgconfig:\$PKG_CONFIG_PATH\""
