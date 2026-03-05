# Building Flux

## Prerequisites

Install Homebrew, then:

```bash
brew install meson ninja pkg-config nasm cmake python3
brew install autoconf automake libtool
```

Xcode 16+ with Command Line Tools:
```bash
xcode-select --install
```

## Step 1 — Build FFmpeg (LGPL)

FFmpeg must be built before mpv (mpv depends on it).

```bash
cd Dependencies/Scripts
chmod +x build-ffmpeg-macos.sh
./build-ffmpeg-macos.sh
```

Output: `Dependencies/ffmpeg/` with `lib/` and `include/`.

This takes ~10–15 minutes on Apple Silicon.

## Step 2 — Build mpv (LGPL)

```bash
cd Dependencies/Scripts
chmod +x build-mpv-macos.sh
./build-mpv-macos.sh
```

Output: `Dependencies/mpv/lib/libmpv.dylib` and `Dependencies/mpv/include/mpv/`.

This takes ~5 minutes on Apple Silicon.

## Step 3 — Verify

```bash
# Check no GPL-only libraries are linked
otool -L Dependencies/mpv/lib/libmpv.dylib

# Verify AV1 decode is available (dav1d)
pkg-config --exists dav1d && echo "dav1d: OK"

# Verify VideoToolbox linkage
otool -L Dependencies/mpv/lib/libmpv.dylib | grep VideoToolbox
```

## Step 4 — Open in Xcode

```bash
open Flux.xcworkspace
```

Select the "Flux (macOS)" scheme and build with ⌘B.

## Setting PKG_CONFIG_PATH

The Swift packages use pkg-config to find mpv and FFmpeg. Set:

```bash
export PKG_CONFIG_PATH="$(pwd)/Dependencies/mpv/lib/pkgconfig:$(pwd)/Dependencies/ffmpeg/lib/pkgconfig:$PKG_CONFIG_PATH"
```

Add this to your `~/.zshrc` or `~/.bash_profile` for convenience.

## Troubleshooting

**"mpv/client.h not found"**: Run the build scripts first. Headers are generated into
`Dependencies/mpv/include/` and are not committed to git.

**"library not found for -lmpv"**: Ensure `PKG_CONFIG_PATH` includes the mpv lib directory.

**AV1 plays slowly on M1/M2**: Expected — no hardware AV1 decode on M1/M2. dav1d software
decode is used automatically. For 4K60 AV1 content, M3+ is recommended.

**Dolby Vision Profile 5 looks wrong**: Ensure `vo=gpu-next` is set in mpv options and
libplacebo was compiled into mpv (check build script output).

## Architecture Notes

- `Dependencies/mpv/lib/libmpv.dylib` — dynamically linked on macOS (LGPL requires this)
- For iOS builds (Phase 2), `libmpv.a` static library is built instead (App Store requires static)
- The `CLibMPV` Swift Package target provides Swift-importable headers via `module.modulemap`
