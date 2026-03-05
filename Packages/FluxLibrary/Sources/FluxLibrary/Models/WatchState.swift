import Foundation
import SwiftData

// MARK: - WatchState

/// Tracks playback progress and watch status for a MediaItem.
/// Stored separately for granular CloudKit sync — only this record
/// needs updating when the user watches something.
@Model
public final class WatchState {

    @Attribute(.unique)
    public var id: UUID = UUID()

    // MARK: Relationship

    public var mediaItem: MediaItem?

    // MARK: Progress

    /// Current playback position in seconds.
    public var position: Double = 0

    /// Duration at time of last update (for progress % calculation without full reload).
    public var duration: Double = 0

    /// Progress as 0–1. Returns 0 if duration unknown.
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return position / duration
    }

    /// True if the item has been watched to completion
    /// (position within last 60 seconds of content, or explicitly marked).
    public var isWatched: Bool = false

    /// Number of times played to completion.
    public var playCount: Int = 0

    // MARK: Dates

    public var lastPlayedAt: Date?
    public var lastUpdatedAt: Date = Date()

    // MARK: Init

    public init() {}

    // MARK: Updates

    /// Update position from active playback. Called every ~5 seconds.
    public func update(position: Double, duration: Double) {
        self.position = position
        self.duration = duration
        self.lastPlayedAt = Date()
        self.lastUpdatedAt = Date()

        // Mark watched if within last 60 seconds
        if duration > 60 && position >= duration - 60 {
            markWatched()
        }
    }

    public func markWatched() {
        isWatched = true
        playCount += 1
        position = 0
        lastUpdatedAt = Date()
    }

    public func markUnwatched() {
        isWatched = false
        position = 0
        lastUpdatedAt = Date()
    }

    // MARK: Display

    public var hasProgress: Bool {
        !isWatched && position > 30
    }

    public var remainingMinutes: Int {
        guard duration > 0 else { return 0 }
        return Int(ceil((duration - position) / 60))
    }
}
