import Foundation
import VideoToolbox

// MARK: - Codec Support

/// Represents a codec's hardware decode support level on the current device.
public enum HWDecodeSupport: Sendable {
    case hardware    // Full VideoToolbox hardware decode
    case software    // Software fallback (dav1d, libavcodec, etc.)
    case unsupported // Codec not supported at all
}

// MARK: - HardwareDecoder

/// Queries VideoToolbox at app launch to determine which codecs have hardware
/// acceleration on the current device. Results are cached.
///
/// Apple Silicon hardware decode support:
/// - H.264: All M-series
/// - HEVC: All M-series (Main, Main10, Main 4:2:2, 4:4:4)
/// - AV1:  M3+ hardware; M1/M2 use dav1d software (~50fps 4K)
/// - VP9:  All M-series (VideoToolbox, macOS 11+)
/// - ProRes: All M-series (dedicated Media Engine)
public final class HardwareDecoder: Sendable {

    public static let shared = HardwareDecoder()

    // MARK: Codec Support

    public let h264: HWDecodeSupport
    public let hevc: HWDecodeSupport
    public let av1: HWDecodeSupport
    public let vp9: HWDecodeSupport
    public let prores: HWDecodeSupport

    /// Recommended mpv `hwdec` option string based on current hardware.
    public var mpvHWDecOption: String { "auto" }

    /// Additional mpv options based on detected hardware.
    public var mpvOptions: [String: String] {
        var opts: [String: String] = [:]
        opts["hwdec"] = "auto"
        opts["hwdec-codecs"] = hwDecCodecs
        return opts
    }

    private var hwDecCodecs: String {
        var codecs: [String] = []
        if h264 == .hardware   { codecs.append("h264") }
        if hevc == .hardware   { codecs.append("hevc") }
        if av1  == .hardware   { codecs.append("av1") }
        if vp9  == .hardware   { codecs.append("vp9") }
        if prores == .hardware { codecs.append("prores") }
        return codecs.isEmpty ? "no" : codecs.joined(separator: ",")
    }

    // MARK: Init

    private init() {
        h264   = Self.check(kCMVideoCodecType_H264)
        hevc   = Self.check(kCMVideoCodecType_HEVC)
        av1    = Self.checkAV1()
        vp9    = Self.check(kCMVideoCodecType_VP9)
        prores = Self.check(kCMVideoCodecType_AppleProRes422)
    }

    // MARK: Private

    private static func check(_ codec: CMVideoCodecType) -> HWDecodeSupport {
        var supported: DarwinBoolean = false
        VTIsHardwareDecodeSupported(codec, &supported)
        return supported.boolValue ? .hardware : .software
    }

    private static func checkAV1() -> HWDecodeSupport {
        // AV1 hardware decode available on M3+ (kCMVideoCodecType_AV1 = 'av01')
        let av1CodecType = CMVideoCodecType(0x61763031) // 'av01'
        var supported: DarwinBoolean = false
        VTIsHardwareDecodeSupported(av1CodecType, &supported)
        return supported.boolValue ? .hardware : .software
        // M1/M2: returns .software — dav1d is used automatically via FFmpeg
    }
}

// MARK: - Logging

extension HardwareDecoder: CustomStringConvertible {
    public var description: String {
        """
        HardwareDecoder:
          H.264:   \(h264)
          HEVC:    \(hevc)
          AV1:     \(av1) \(av1 == .software ? "(dav1d)" : "")
          VP9:     \(vp9)
          ProRes:  \(prores)
          mpv hwdec-codecs: \(hwDecCodecs)
        """
    }
}
