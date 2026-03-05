#!/usr/bin/env bash
# build-ffmpeg-macos.sh — Builds FFmpeg as LGPL for Flux
# Output: Dependencies/ffmpeg/{lib,include}
#
# LGPL compliance: built WITHOUT --enable-gpl.
# No GPL codecs (x264, x265, libxvid) are included.
# x264/x265 decoders are in LGPL FFmpeg — only their encoders require GPL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/Dependencies/ffmpeg"
BUILD_DIR="$REPO_ROOT/Dependencies/build/ffmpeg"
FFMPEG_VERSION="7.1"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"

# Architectures for universal binary
ARCHS=("arm64" "x86_64")
MACOS_MIN="12.0"

echo "==> Building FFmpeg ${FFMPEG_VERSION} (LGPL) for macOS"
echo "    Output: $OUTPUT_DIR"

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Download FFmpeg source
TARBALL="$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}.tar.xz"
if [ ! -f "$TARBALL" ]; then
    echo "==> Downloading FFmpeg ${FFMPEG_VERSION}..."
    curl -L "$FFMPEG_URL" -o "$TARBALL"
fi

# Extract
SOURCE_DIR="$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}"
if [ ! -d "$SOURCE_DIR" ]; then
    echo "==> Extracting..."
    tar -xf "$TARBALL" -C "$BUILD_DIR"
fi

build_for_arch() {
    local ARCH="$1"
    local INSTALL_DIR="$BUILD_DIR/install-${ARCH}"
    mkdir -p "$INSTALL_DIR"

    echo "==> Configuring FFmpeg for ${ARCH}..."
    pushd "$SOURCE_DIR" > /dev/null

    # Set up cross-compile environment for the target arch
    if [ "$ARCH" = "arm64" ]; then
        EXTRA_CFLAGS="-arch arm64"
        EXTRA_LDFLAGS="-arch arm64"
        HOST="aarch64-apple-darwin"
    else
        EXTRA_CFLAGS="-arch x86_64"
        EXTRA_LDFLAGS="-arch x86_64"
        HOST="x86_64-apple-darwin"
    fi

    ./configure \
        --prefix="$INSTALL_DIR" \
        --enable-cross-compile \
        --arch="${ARCH}" \
        --target-os="darwin" \
        --cc="clang" \
        --cxx="clang++" \
        --extra-cflags="${EXTRA_CFLAGS} -mmacosx-version-min=${MACOS_MIN}" \
        --extra-ldflags="${EXTRA_LDFLAGS} -mmacosx-version-min=${MACOS_MIN}" \
        \
        `# === LGPL compliance: NO --enable-gpl ===` \
        --disable-gpl \
        --disable-nonfree \
        \
        `# Disable unnecessary components to reduce size` \
        --disable-programs \
        --disable-doc \
        --disable-debug \
        \
        `# Enable hardware acceleration` \
        --enable-videotoolbox \
        --enable-audiotoolbox \
        \
        `# AV1 software decode (dav1d) — used on M1/M2` \
        --enable-libdav1d \
        \
        `# Subtitles` \
        --enable-libass \
        --enable-libfribidi \
        --enable-libharfbuzz \
        \
        `# Network protocols` \
        --enable-protocol=http \
        --enable-protocol=https \
        --enable-protocol=tcp \
        --enable-protocol=udp \
        --enable-protocol=file \
        --enable-protocol=ftp \
        \
        `# Core decoders — all LGPL` \
        --enable-decoder=h264 \
        --enable-decoder=hevc \
        --enable-decoder=av1 \
        --enable-decoder=vp8 \
        --enable-decoder=vp9 \
        --enable-decoder=mpeg2video \
        --enable-decoder=mpeg4 \
        --enable-decoder=wmv3 \
        --enable-decoder=vc1 \
        --enable-decoder=prores \
        --enable-decoder=dnxhd \
        --enable-decoder=mjpeg \
        --enable-decoder=theora \
        --enable-decoder=flac \
        --enable-decoder=aac \
        --enable-decoder=ac3 \
        --enable-decoder=eac3 \
        --enable-decoder=mp3 \
        --enable-decoder=opus \
        --enable-decoder=vorbis \
        --enable-decoder=truehd \
        --enable-decoder=dts \
        --enable-decoder=pcm_s16le \
        --enable-decoder=pcm_s24le \
        --enable-decoder=pcm_s32le \
        --enable-decoder=subrip \
        --enable-decoder=ass \
        --enable-decoder=hdmv_pgs_subtitle \
        --enable-decoder=dvdsub \
        \
        `# Demuxers` \
        --enable-demuxer=matroska \
        --enable-demuxer=mov \
        --enable-demuxer=mp4 \
        --enable-demuxer=avi \
        --enable-demuxer=mpegts \
        --enable-demuxer=mpegps \
        --enable-demuxer=flv \
        --enable-demuxer=ogg \
        --enable-demuxer=flac \
        --enable-demuxer=webm \
        --enable-demuxer=hls \
        --enable-demuxer=dash \
        \
        `# Shared library` \
        --enable-shared \
        --disable-static \
        --install-name-dir="@rpath"

    make -j"$(sysctl -n hw.logicalcpu)"
    make install

    popd > /dev/null
    echo "==> Done: FFmpeg ${ARCH}"
}

# Build for each architecture
for ARCH in "${ARCHS[@]}"; do
    build_for_arch "$ARCH"
done

# Create universal binaries with lipo
echo "==> Creating universal binaries..."
mkdir -p "$OUTPUT_DIR/lib" "$OUTPUT_DIR/include"

# Copy headers from arm64 build
cp -r "$BUILD_DIR/install-arm64/include/"* "$OUTPUT_DIR/include/"

# Lipo each dylib
for LIB in "$BUILD_DIR/install-arm64/lib/"*.dylib; do
    LIBNAME="$(basename "$LIB")"
    # Follow symlinks to get real file
    ARM64_LIB="$BUILD_DIR/install-arm64/lib/$LIBNAME"
    X86_LIB="$BUILD_DIR/install-x86_64/lib/$LIBNAME"
    if [ -f "$X86_LIB" ]; then
        lipo -create "$ARM64_LIB" "$X86_LIB" -output "$OUTPUT_DIR/lib/$LIBNAME"
    else
        cp "$ARM64_LIB" "$OUTPUT_DIR/lib/$LIBNAME"
    fi
done

# Copy pkgconfig
mkdir -p "$OUTPUT_DIR/lib/pkgconfig"
cp "$BUILD_DIR/install-arm64/lib/pkgconfig/"*.pc "$OUTPUT_DIR/lib/pkgconfig/"
# Fix prefix in .pc files
for PC in "$OUTPUT_DIR/lib/pkgconfig/"*.pc; do
    sed -i '' "s|prefix=$BUILD_DIR/install-arm64|prefix=$OUTPUT_DIR|g" "$PC"
done

echo ""
echo "==> FFmpeg LGPL build complete."
echo "    Libraries: $OUTPUT_DIR/lib/"
echo "    Headers:   $OUTPUT_DIR/include/"
echo ""
echo "==> Verifying no GPL contamination..."
otool -L "$OUTPUT_DIR/lib/libavcodec.dylib" | grep -E "(x264|x265|libxvid)" && echo "WARNING: GPL library found!" || echo "LGPL verification: OK"
