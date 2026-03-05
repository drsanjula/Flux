# Flux — Commercial Media Player: Research & Architecture Plan

## Vision

**Flux** is a native Apple platform media player built for the modern era. It plays anything — every codec, every container, every format — with hardware-accelerated decoding, a beautiful poster-grid library, automatic metadata, and streaming server integration.

The gap in the market: existing players are either technically excellent but feature-sparse, or feature-rich but built on aging backends. Flux targets power users and home theater enthusiasts who want the full package without compromises.

**Platforms**: macOS first (Phase 1), iOS/tvOS in later phases.
**Business model**: $1/month or $10/year subscription, competitive with the $9.99/year market standard.

---

## Codec Completeness — Research Findings

This is the core technical requirement. Here's the state of every major codec on Apple Silicon macOS.

### Hardware-Accelerated Decode (VideoToolbox)

| Codec | Apple Silicon Support | Notes |
|---|---|---|
| H.264 (AVC) | All M-series | All profiles; zero-copy path via VideoToolbox |
| HEVC (H.265) | All M-series | Main, Main10, Main 4:2:2, Main 4:4:4, Monochrome12 |
| AV1 | M3, M4 hardware; M1/M2 software | dav1d software decoder fast enough for real-time 4K on M1/M2 |
| VP9 | All M-series (VideoToolbox) | Supported since macOS 11 |
| ProRes / ProRes RAW | All M-series (Media Engine) | Dedicated Media Engine hardware |
| MPEG-2 | Software only | Legacy; acceptable for DVD rips |
| VC-1 | Software only | Legacy WMV; acceptable performance |

**AV1 on M1/M2**: dav1d achieves ~50fps at 4K on M1 without hardware acceleration. For 4K60 it may dip below real-time — acceptable for most content. Use `--enable-libdav1d` in FFmpeg build; mpv will prefer it automatically.

**VideoToolbox**: All hardware decode goes through VideoToolbox. mpv uses `hwdec=auto` to pick it automatically. Zero-copy path — decoded frames stay in GPU memory, no CPU round-trip.

### Dolby Vision — The Real Picture

**Critical finding**: No third-party macOS app achieves Dolby Vision *display passthrough*. macOS Sequoia added HDMI passthrough for Dolby Atmos audio but **not for Dolby Vision video**. This is a platform limitation — it affects every player equally.

**What IS achievable — a hybrid decode strategy**:

| DV Profile | Common Source | Strategy | Quality |
|---|---|---|---|
| Profile 8 (base + enhancement) | Disney+, Apple TV rips | AVFoundation automatic decode | Native, no tone-mapping loss |
| Profile 5 (DV-only, no SDR base) | Most UHD Blu-ray rips | mpv + libplacebo tone-mapping | High-quality SDR output |
| Profile 7 (broadcast) | Rare | mpv + libplacebo tone-mapping | Good |

**Implementation**: AVFoundation handles Profile 8 automatically (Apple's native path). For Profile 5/7, route to mpv with `vo=gpu-next` + libplacebo tone-mapping. This is better DV support than most competitors offer.

**Tone-mapping config** (mpv, `gpu-next` VO):
- `--tone-mapping=bt.2390` — perceptual, best quality
- `--hdr-compute-peak=yes` — dynamic peak detection
- `--target-colorspace-hint=yes` — pass display color space info

### HDR10 & HDR10+

- **HDR10 passthrough**: Not achievable via third-party APIs on macOS. Platform limitation.
- **HDR10 tone-mapping**: mpv with `gpu-next` + libplacebo handles this well, configurable.
- **HDR10+** (dynamic HDR): No macOS player supports this yet. Platform limitation.
- **HLG**: mpv handles tone-mapping.

### Codec Completeness (LGPL FFmpeg Build)

All major video codecs are available as **decoders** in LGPL FFmpeg:
- H.264, HEVC, AV1, VP8, VP9, MPEG-2, VC-1, ProRes, DNxHD, MJPEG, Theora, H.263, MPEG-4 Part 2, WMV3

**What's only in GPL FFmpeg** (lost with `--enable-gpl` removed):
- x264, x265 **encoders** only (GPL) — their **decoders** remain in LGPL. We are a player, not an encoder. **No relevant decoder loss.**
- yadif deinterlace filter — minimal impact (modern streaming rips are progressive)

**Conclusion**: LGPL FFmpeg loses nothing that matters to a media player user.

### Premium Differentiator: AI Upscaling via ANE

Apple Silicon's Neural Engine (ANE) is accessible via CoreML. Real-ESRGAN converted to CoreML achieves **78x speedup vs CPU** with **75% lower power** — enabling frame-level AI upscaling (SD→HD, 720p→4K) at real-time speeds on M-series chips.

No existing commercial macOS player offers this. Phase 2 premium feature:
- CoreML + Real-ESRGAN for per-frame upscaling
- Integration point: post-decode, pre-render in the Metal pipeline
- Exposed as "Super Resolution" toggle in player settings

---

## Technology Stack

| Layer | Choice | Justification |
|---|---|---|
| Language | **Swift 6** | Actor model prevents media threading bugs at compile time; strict concurrency |
| UI framework | **SwiftUI + targeted AppKit** | Modern declarative; video surface requires NSView via NSViewRepresentable |
| Media engine | **mpv LGPL build + libmpv C API** | VideoToolbox, libass subtitles, libplacebo HDR tone-mapping; libmpv API is ISC-licensed |
| DV Profile 8 | **AVFoundation bridge** | Apple's native DV decode, used selectively for P8 content |
| Rendering | **Metal via CAMetalLayer + IOSurface** | Zero-copy GPU decode, HDR metadata passthrough, CADisplayLink frame pacing |
| Upscaling | **CoreML + Real-ESRGAN** (Phase 2) | ANE acceleration, unique differentiator |
| Persistence | **SwiftData** | Native, actor-isolated, CloudKit-ready |
| Sync | **CloudKit** | Per-record conflict resolution for watch state sync |
| Build system | **Xcode project + local Swift Packages** | Code signing, entitlements, clean module boundaries |
| Distribution | **Mac App Store + direct (Paddle)** | Discoverability + better margin on direct |
| Subscriptions | **StoreKit 2** | Cross-platform entitlement sharing (macOS purchase unlocks iOS) |

---

## Architecture: Module Structure

```
Flux/
├── Flux.xcworkspace
├── App/
│   ├── Flux.xcodeproj          ← multi-platform Xcode project
│   ├── macOS/                  ← macOS entry points + AppDelegate
│   ├── iOS/                    ← iOS entry points (Phase 2)
│   └── Shared/                 ← cross-platform root views
├── Packages/
│   ├── FluxCore/               ← media engine
│   │   ├── MPVClient.swift     ← Swift actor wrapping mpv_handle
│   │   ├── MPVRenderContext.swift  ← Metal/IOSurface render context
│   │   ├── VideoSurface.swift  ← NSView backed by CAMetalLayer
│   │   ├── MediaSession.swift  ← @Observable playback state → SwiftUI
│   │   ├── DVDecoder.swift     ← DV profile detection + AVFoundation bridge
│   │   ├── HardwareDecoder.swift  ← VideoToolbox capability detection at launch
│   │   └── CLibMPV/            ← C target + module.modulemap for libmpv headers
│   ├── FluxLibrary/            ← library management
│   │   ├── MediaLibrary.swift  ← SwiftData store
│   │   ├── LibraryScanner.swift
│   │   ├── Models/             ← MediaItem, MediaMetadata, WatchState
│   │   └── NetworkSources/     ← SMB, Plex, Jellyfin, Emby, WebDAV
│   ├── FluxMetadata/           ← metadata/artwork fetching
│   │   ├── TMDbClient.swift
│   │   ├── TVDBClient.swift
│   │   ├── MetadataMatchingEngine.swift
│   │   └── ArtworkCache.swift  ← NSCache + disk, vImage resizing
│   ├── FluxSubtitles/          ← subtitle management
│   │   ├── SubtitleTrack.swift
│   │   └── OpenSubtitlesClient.swift
│   ├── FluxUpscaling/          ← Phase 2: ANE/CoreML upscaling
│   │   ├── SuperResolutionEngine.swift
│   │   └── RealESRGAN.mlpackage
│   └── FluxUI/                 ← shared UI components
│       ├── Theme/FluxTheme.swift
│       ├── Library/PosterGridView.swift
│       └── Player/PlayerControlsView.swift
└── Dependencies/
    ├── mpv/                    ← built library output (.gitignored)
    └── Scripts/
        ├── build-mpv-macos.sh  ← meson, -Dgpl=false, arm64+x86_64 universal
        └── build-ffmpeg-macos.sh  ← LGPL, --enable-libdav1d, no --enable-gpl
```

---

## Core Component Design

### FluxCore — Media Engine

**`HardwareDecoder`** — runs at app launch, queries VideoToolbox for available codecs:
```
VideoToolboxSupports(kCMVideoCodecType_HEVC) → hwdec=videotoolbox
VideoToolboxSupports(kCMVideoCodecType_AV1)  → hwdec=videotoolbox (M3+)
                                             → dav1d software fallback (M1/M2)
```
Sets mpv options dynamically based on hardware. Users never need to configure this.

**`DVDecoder`** — inspects `AVAsset` for Dolby Vision profile before opening:
- Profile 8 → `AVPlayer` + `AVPlayerLayer` (Apple native path, automatic)
- Profile 5/7 → mpv with `vo=gpu-next`, `tone-mapping=bt.2390`
- No DV → mpv with `hwdec=auto`

**`MPVClient` (Swift actor)** — owns `mpv_handle`, all API calls serialized by actor isolation. Playback commands are `async func`. Property observations exposed as `AsyncStream<MPVEvent>`.

**`MPVRenderContext`** — manages `mpv_render_context` with Metal-backed `IOSurface`. Frame pacing via `CADisplayLink`. Uses `gpu-next` VO for libplacebo HDR tone-mapping.

**`MediaSession` (@Observable)** — bridges engine to SwiftUI. Holds: position, duration, paused, track list, chapters, HDR mode, DV profile. Manages `MPRemoteCommandCenter` (Control Center, AirPods, lock screen).

### FluxLibrary — Library Management

SwiftData schema:
- `MediaItem`: file URL, security-scoped bookmark (macOS sandbox), format info, DV/HDR flags
- `MediaMetadata`: TMDb/TVDB data, poster/backdrop URLs, cast, genres, year
- `WatchState`: position (seconds), watched flag, last-played date, user rating

`LibraryScanner`: background actor, `FileManager.AsyncEnumerator`, identifies media by UTType. Inspects HDR/DV metadata via lightweight `AVAsset` probing (no full decode).

`MediaSource` protocol: async `list()`, `search()`, `resolve()`. Implementations: `LocalFileSource`, `SMBSource`, `PlexSource`, `JellyfinSource`, `EmbySource`, `WebDAVSource`.

### FluxMetadata — Metadata Engine

`MetadataMatchingEngine`:
1. Filename regex parsing: `Movie.2023.1080p.BluRay...` → title + year; `Show.S01E03...` → series + episode
2. TMDb (movies/shows) + TVDB (TV episodes) queries
3. Candidate scoring: title similarity (Levenshtein) + year proximity
4. Auto-select if confidence > 0.85; surface disambiguation UI otherwise

`ArtworkCache`: in-memory `NSCache` + disk cache in Application Support. `vImage` for thumbnail/poster/backdrop size generation. HTTP caching headers respected.

### FluxUI — UI Layer (macOS)

- `NavigationSplitView`: sidebar (Library / Sources / Collections) + `LazyVGrid` poster content area
- `PosterGridView`: fixed 2:3 aspect ratio cells, hover effects via `onHover`, async artwork loading
- `PlayerControlsView`: custom scrubber with chapter marker overlays, audio/subtitle track pickers, volume, fullscreen, PiP
- `MetadataDetailView`: backdrop + cast + overview + related content
- `FluxTheme`: environment value with dark-first color palette, SF typography, spacing scale

---

## Phased Delivery

### Phase 1: macOS MVP (months 1–8)
**Core playback — no compromises:**
- H.264, HEVC, AV1, VP9, VP8, MPEG-2, VC-1, ProRes, DNxHD
- All containers: MKV, MP4, MOV, AVI, M2TS, ISO, TS
- Hardware decode via VideoToolbox (auto-detected per chip)
- AV1: hardware on M3+, dav1d software on M1/M2
- Dolby Vision: Profile 8 via AVFoundation; Profile 5/7 via mpv tone-mapping
- HDR10: libplacebo tone-mapping (`gpu-next` VO)
- SRT/ASS/VTT/PGS subtitles (embedded + external, via libass)
- SwiftUI poster-grid library with TMDb metadata + artwork
- Scrubber with chapter markers, audio/subtitle track switching, volume, fullscreen, PiP
- Persistent play position per file
- Dark mode first, native macOS

**Explicitly deferred:** SMB/NFS, Plex/Emby/Jellyfin, iCloud sync, iOS/tvOS, AI upscaling

### Phase 2: Ecosystem + AI (months 9–14)
- SMB/WebDAV/NFS network share browsing
- Plex, Jellyfin, Emby integration (OAuth via `ASWebAuthenticationSession`)
- CloudKit `WatchState` sync (per-record, conflict-resolved)
- iOS/iPadOS port (same FluxCore/FluxLibrary packages, touch-adapted UI)
- **Super Resolution**: CoreML Real-ESRGAN via ANE — unique market differentiator

### Phase 3: tvOS & Advanced (months 15–20)
- tvOS: Focus engine navigation, Top Shelf extension, GCController remote support
- Playlist/queue management
- Advanced audio: DTS passthrough configuration, surround downmix options

### Phase 4: visionOS (months 21+)
- Defer until platform install base justifies investment

---

## Commercial Strategy

**Model**: Subscription
- **$1/month** or **$10/year** (annual preferred — less friction, matches market standard)
- Free tier: basic file playback, 5-file library limit, no metadata, no streaming
- Flux Pro: unlimited library, auto metadata + artwork, network shares, streaming servers, iCloud sync, Super Resolution (Phase 2)

**Distribution**:
- Mac App Store (primary — discoverability, lower support overhead)
- Direct via Paddle (better margin, own activation; alternative for App Store avoiders)
- iOS/tvOS: App Store only (no viable alternative at commercial scale)
- StoreKit 2 cross-platform entitlements: one subscription unlocks all platforms

**Positioning**: Lead with codec completeness and DV/HDR handling. Power users and home theater enthusiasts choose a player based on what it can play — make that the headline.

---

## Licensing Compliance

### LGPL Compliance (mpv + FFmpeg)
1. **Build scripts public**: Host `build-mpv-macos.sh` + exact mpv version on GitHub. Link from app About screen.
2. **Dynamic linking on macOS**: `libmpv.dylib` in app bundle satisfies LGPL "user can replace library" requirement.
3. **Static linking on iOS** (Phase 2): Accepted practice — provide build scripts publicly. Formal legal review required before iOS App Store submission.
4. **Attribution UI**: "Open Source Licenses" screen with mpv, FFmpeg, libass, libplacebo, dav1d, fribidi, freetype license texts.

### GPL Contamination — Never Include
- `--enable-gpl` in FFmpeg build (adds x264, x265, yadif)
- mpv built without `-Dgpl=false`
- x264, x265, FAAD2, libdvdcss
- libfdk-aac (use Apple's AAC decoder via VideoToolbox instead)

### Safe LGPL/Permissive Libraries
mpv LGPL, libmpv (ISC), FFmpeg LGPL, libass (ISC), libplacebo (LGPL), libbluray (LGPL), dav1d (BSD-2), freetype (FTL), fribidi (LGPL)

### Third-Party API Licensing
- **TMDb**: Commercial license required (partnerships@themoviedb.org) — contact before launch
- **TheTVDB**: Commercial API tier (v4)
- **OpenSubtitles**: Commercial API plan for user-facing apps
- **MusicBrainz**: CC-licensed data, free with attribution

---

## Bootstrap Sequence

Order matters — mpv must be buildable before the Xcode project can compile.

**Step 1 — Foundation**
- `README.md`, `.gitignore` (Swift/Xcode standard), `LICENSING.md`

**Step 2 — mpv Build Infrastructure** ← do this before writing any Swift
- `Dependencies/Scripts/build-mpv-macos.sh` — meson, `-Dgpl=false`, `--enable-libdav1d`, arm64+x86_64 universal
- `Dependencies/Scripts/build-ffmpeg-macos.sh` — `--enable-libdav1d`, no `--enable-gpl`
- `Dependencies/mpv/.gitkeep`
- `BUILDING.md` — developer onboarding: run build scripts first, then open Xcode

**Step 3 — FluxCore Swift Package**
- `Packages/FluxCore/Package.swift`
- `Packages/FluxCore/Sources/CLibMPV/module.modulemap`
- `Packages/FluxCore/Sources/FluxCore/MPVClient.swift`
- `Packages/FluxCore/Sources/FluxCore/HardwareDecoder.swift`
- `Packages/FluxCore/Sources/FluxCore/PlaybackState.swift`

**Step 4 — Xcode Project + Workspace**
- `App/Flux.xcodeproj` — macOS target; entitlements: App Sandbox, network client, user-selected files read/write
- `App/macOS/FluxApp.swift`
- `App/Shared/RootView.swift`
- `Flux.xcworkspace`

**Step 5 — Remaining Package Stubs**
- `Packages/FluxLibrary/`, `Packages/FluxMetadata/`, `Packages/FluxSubtitles/`, `Packages/FluxUI/`

---

## Critical Files

| File | Why Critical |
|---|---|
| `Dependencies/Scripts/build-mpv-macos.sh` | Nothing compiles without the built library. Must include `-Dgpl=false` and dav1d flags. Write and validate this first. |
| `Packages/FluxCore/Sources/CLibMPV/module.modulemap` | Bridge between C libmpv headers and Swift. Wrong paths block all FluxCore compilation. |
| `Packages/FluxCore/Sources/FluxCore/MPVClient.swift` | Actor wrapping `mpv_handle`. All components depend on its async API surface. |
| `Packages/FluxCore/Sources/FluxCore/DVDecoder.swift` | DV profile detection and routing (mpv vs AVFoundation). Wrong routing = broken DV playback. |
| `Packages/FluxLibrary/Sources/FluxLibrary/Models/MediaItem.swift` | SwiftData schema anchor. Security-scoped bookmark design must be correct before library or UI is built. |
| `App/Flux.xcodeproj` | Entitlements, library search paths for libmpv, code signing. Most time-intensive setup. |

---

## Verification Checklist

1. **mpv LGPL build**: `build-mpv-macos.sh` produces `libmpv.dylib`; `otool -L` shows no GPL-only dependencies
2. **Codec matrix**: Play test files for H.264, HEVC, AV1, VP9, MPEG-2, VC-1, ProRes; verify `hwdec-current = videotoolbox` for hardware-capable codecs
3. **AV1 chip fallback**: On M1/M2 verify AV1 decodes via dav1d; on M3+ verify `hwdec-current = videotoolbox`
4. **DV Profile 8**: File with DV8 metadata → AVFoundation path → correct colors on display
5. **DV Profile 5**: UHD rip with DV5 → mpv `gpu-next` → viewable tone-mapped SDR output
6. **HDR10**: HDR10 MKV → libplacebo tone-map → no highlight clipping, natural appearance on SDR display
7. **Subtitles**: ASS, SRT, PGS embedded tracks render correctly via libass
8. **Metadata match**: `The.Dark.Knight.2008.1080p.mkv` → TMDb ID 155, confidence > 0.85
9. **LGPL compliance**: `otool -L Flux.app/Contents/MacOS/Flux` shows `libmpv.dylib` dynamic; no GPL-only dylibs in bundle
10. **Sandbox compliance**: Security-scoped bookmarks persist across app launches; no crashes on folder access
