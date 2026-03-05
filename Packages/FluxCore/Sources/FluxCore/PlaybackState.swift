import Foundation
import Observation

// MARK: - Track

public struct MediaTrack: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable {
        case video, audio, sub
    }
    public let id: Int
    public let kind: Kind
    public let title: String?
    public let language: String?
    public let codec: String?
    public let isDefault: Bool
    public let isSelected: Bool
    public let isExternal: Bool
}

// MARK: - Chapter

public struct MediaChapter: Identifiable, Sendable, Hashable {
    public let id: Int  // index
    public let title: String
    public let time: Double  // start time in seconds
}

// MARK: - Playback Status

public enum PlaybackStatus: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case ended
    case error(String)
}

// MARK: - Video Info

public struct VideoInfo: Sendable {
    public let codec: String?
    public let hwDecoder: String?   // e.g. "videotoolbox", "no"
    public let isHDR: Bool
    public let isDolbyVision: Bool
    public let dvProfile: Int?
}

// MARK: - PlaybackState

/// Observable state for all playback parameters.
/// Updated from MPVClient events. Consumed by SwiftUI views.
@Observable
public final class PlaybackState: @unchecked Sendable {

    // MARK: Playback

    public var status: PlaybackStatus = .idle
    public var isPlaying: Bool = false
    public var currentTime: Double = 0
    public var duration: Double = 0
    public var bufferedTime: Double = 0

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    public var remainingTime: Double {
        max(0, duration - currentTime)
    }

    // MARK: Volume

    public var volume: Double = 100
    public var isMuted: Bool = false

    // MARK: Tracks

    public var tracks: [MediaTrack] = []

    public var videoTracks: [MediaTrack] { tracks.filter { $0.kind == .video } }
    public var audioTracks: [MediaTrack] { tracks.filter { $0.kind == .audio } }
    public var subtitleTracks: [MediaTrack] { tracks.filter { $0.kind == .sub } }

    public var selectedAudioTrack: MediaTrack? { audioTracks.first(where: \.isSelected) }
    public var selectedSubtitleTrack: MediaTrack? { subtitleTracks.first(where: \.isSelected) }

    // MARK: Chapters

    public var chapters: [MediaChapter] = []
    public var currentChapter: Int = 0

    // MARK: Video Info

    public var videoInfo: VideoInfo?

    // MARK: Current Item

    public var currentURL: URL?
    public var currentTitle: String?

    // MARK: Init

    public init() {}
}
