# Licensing

## Flux Application

Flux is proprietary software. All application source code is copyright its authors.

---

## Open Source Components

Flux uses the following open source libraries. Their licenses are reproduced in full
in the app's "Open Source Licenses" screen (Settings → About → Open Source Licenses).

### mpv
- License: LGPL-2.1+
- Built with `-Dgpl=false` (no GPL components included)
- Source: https://github.com/mpv-player/mpv
- Build scripts: `Dependencies/Scripts/build-mpv-macos.sh`

### libmpv C API
- License: ISC
- Part of the mpv project

### FFmpeg
- License: LGPL-2.1+
- Built without `--enable-gpl` (no GPL components included)
- Source: https://ffmpeg.org/
- Build scripts: `Dependencies/Scripts/build-ffmpeg-macos.sh`

### libass
- License: ISC
- Source: https://github.com/libass/libass

### libplacebo
- License: LGPL-2.1+
- Source: https://github.com/haasn/libplacebo

### dav1d
- License: BSD 2-Clause
- Source: https://code.videolan.org/videolan/dav1d

### freetype
- License: FTL (FreeType License, permissive)
- Source: https://freetype.org/

### fribidi
- License: LGPL-2.1+
- Source: https://github.com/fribidi/fribidi

### harfbuzz
- License: MIT
- Source: https://harfbuzz.github.io/

---

## LGPL Compliance

Flux dynamically links against mpv (`libmpv.dylib`) and FFmpeg (`libavcodec.dylib`,
`libavformat.dylib`, etc.) on macOS. Users may replace these libraries with a
modified version compiled from the same source code.

To build the LGPL-compliant versions used by Flux, see `BUILDING.md`.

The source code for all LGPL components is available at the URLs listed above.
The exact versions and build configurations used are pinned in the build scripts.

---

## Third-Party APIs

- **TMDb** — The Movie Database: Used under commercial license. Attribution required.
  "This product uses the TMDb API but is not endorsed or certified by TMDb."
- **TheTVDB** — Used under commercial API license.
- **OpenSubtitles** — Used under commercial API license.
- **MusicBrainz** — CC0-licensed data. Free to use with attribution.
