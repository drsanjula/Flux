import Foundation
import AVFoundation

// MARK: - Dolby Vision Profile

/// Dolby Vision profiles found in media files.
/// Reference: https://professionalsupport.dolby.com/s/article/What-is-Dolby-Vision-Profile
public enum DVProfile: Int, Sendable {
    case profile4 = 4   // HEVC + enhancement, base is HDR10
    case profile5 = 5   // HEVC single-layer DV only (no HDR base) — common in Blu-ray rips
    case profile7 = 7   // HEVC dual-layer, broadcast
    case profile8 = 8   // HEVC + enhancement over SDR base — Apple TV/Disney+ common
    case profile9 = 9   // AVC base, broadcast/streaming

    /// Whether this profile has an HDR10 or SDR base layer that can be decoded
    /// without DV-specific tone-mapping.
    public var hasUsableBaseLayer: Bool {
        switch self {
        case .profile8, .profile4: return true
        case .profile5, .profile7, .profile9: return false
        }
    }

    /// Human-readable description for UI.
    public var displayName: String {
        "Dolby Vision Profile \(rawValue)"
    }
}

// MARK: - HDR Format

public enum HDRFormat: Sendable, CustomStringConvertible {
    case sdr
    case hdr10
    case hdr10Plus
    case hlg
    case dolbyVision(profile: DVProfile)

    public var description: String {
        switch self {
        case .sdr:                         return "SDR"
        case .hdr10:                       return "HDR10"
        case .hdr10Plus:                   return "HDR10+"
        case .hlg:                         return "HLG"
        case .dolbyVision(let p):          return p.displayName
        }
    }

    public var isDolbyVision: Bool {
        if case .dolbyVision = self { return true }
        return false
    }

    public var isHDR: Bool { self != .sdr }
}

extension HDRFormat: Equatable {}

// MARK: - Decode Strategy

public enum DVDecodeStrategy: Sendable {
    /// Use AVFoundation (AVPlayer + AVPlayerLayer).
    /// Best for DV Profile 8 — Apple's native path, no tone-mapping loss.
    case avFoundation

    /// Use mpv with `vo=gpu-next` + libplacebo tone-mapping.
    /// Best for DV Profile 5/7 which have no usable SDR/HDR base layer.
    case mpvWithToneMapping
}

// MARK: - DVDecoder

/// Inspects media files to detect Dolby Vision profile and recommends
/// the best decode strategy for macOS.
///
/// On macOS, no third-party player can pass DV through to a DV display
/// (platform limitation as of macOS Sequoia). Instead:
/// - Profile 8: AVFoundation handles automatically with full quality
/// - Profile 5/7: mpv + libplacebo tone-mapping produces high-quality SDR
public enum DVDecoder {

    // MARK: Detection

    /// Detects the HDR format of a media file.
    /// Uses lightweight AVAsset inspection — no full decode.
    public static func detectHDRFormat(url: URL) async -> HDRFormat {
        let asset = AVURLAsset(url: url)

        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return .sdr }

            let formatDescriptions = try await track.load(.formatDescriptions)
            guard let format = formatDescriptions.first else { return .sdr }

            return hdrFormat(from: format as CMFormatDescription)
        } catch {
            return .sdr
        }
    }

    /// Recommends the best decode strategy for a given HDR format on macOS.
    public static func decodeStrategy(for format: HDRFormat) -> DVDecodeStrategy {
        switch format {
        case .dolbyVision(let profile):
            // Profile 8: AVFoundation handles it natively (best quality)
            // Profile 5/7: no usable base layer → mpv tone-mapping
            return profile.hasUsableBaseLayer ? .avFoundation : .mpvWithToneMapping
        default:
            // All other formats (SDR, HDR10, HLG) → mpv
            return .mpvWithToneMapping
        }
    }

    /// mpv options for HDR tone-mapping via libplacebo (gpu-next VO).
    /// Apply these when using mpvWithToneMapping strategy.
    public static var mpvToneMappingOptions: [String: String] {
        [
            "vo":                    "gpu-next",
            "tone-mapping":          "bt.2390",    // perceptual, best quality
            "hdr-compute-peak":      "yes",         // dynamic peak detection
            "target-colorspace-hint": "yes",        // pass display color space
            "tone-mapping-max-boost": "1.0",
        ]
    }

    // MARK: Private

    private static func hdrFormat(from desc: CMFormatDescription) -> HDRFormat {
        let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] ?? [:]

        // Check for Dolby Vision using DOVIConfigurationBox
        if let doviBox = extensions["DOVIConfigurationBox" as String] as? Data,
           let profile = parseDOVIProfile(doviBox) {
            return .dolbyVision(profile: profile)
        }

        // Check color primaries for HDR
        let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
        let transfer  = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String

        if transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) {
            return .hlg
        }
        if primaries == (kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String) {
            if transfer == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) {
                return .hdr10
            }
        }

        return .sdr
    }

    private static func parseDOVIProfile(_ data: Data) -> DVProfile? {
        // DOVIConfigurationBox: 4-byte box size + 4-byte type "dvcC" + profile byte
        guard data.count >= 9 else { return nil }
        let profileByte = data[8]
        let profileNumber = Int(profileByte >> 1) // upper 7 bits
        return DVProfile(rawValue: profileNumber)
    }
}
