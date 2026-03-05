import Foundation
import SwiftData

// MARK: - MediaItem

/// A single playable media file or stream URL.
///
/// `bookmarkData` stores a security-scoped bookmark for sandboxed file access.
/// Always call `startAccessingSecurityScopedResource()` before opening the URL,
/// and `stopAccessingSecurityScopedResource()` when done.
@Model
public final class MediaItem {

    // MARK: Identity

    @Attribute(.unique)
    public var id: UUID = UUID()

    /// Absolute file URL (local) or stream URL (SMB/HTTP).
    public var urlString: String = ""

    /// Security-scoped bookmark for sandboxed access to local files.
    /// Nil for remote URLs (Plex, Jellyfin, SMB streams).
    public var bookmarkData: Data?

    /// Resolved URL from bookmark. Call `resolveURL()` to populate.
    @Transient
    private var _resolvedURL: URL?

    // MARK: Format Info

    public var fileExtension: String = ""
    public var fileSizeBytes: Int64 = 0
    public var containerFormat: String = ""  // "mkv", "mp4", "avi", etc.
    public var videoCodec: String = ""       // "h264", "hevc", "av1", etc.
    public var audioCodec: String = ""
    public var durationSeconds: Double = 0

    // MARK: HDR / Quality

    public var isHDR: Bool = false
    public var isDolbyVision: Bool = false
    public var dvProfile: Int = 0           // 0 = no DV
    public var isHDR10: Bool = false
    public var resolution: String = ""      // "4K", "1080p", "720p", etc.

    // MARK: Source

    public var sourceType: SourceType = .local

    public enum SourceType: String, Codable, Sendable {
        case local
        case smb
        case nfs
        case webdav
        case plex
        case jellyfin
        case emby
        case http
    }

    /// Identifier of the server this item came from (for Plex/Jellyfin).
    public var sourceID: String = ""

    // MARK: Relationships

    @Relationship(deleteRule: .cascade, inverse: \MediaMetadata.mediaItem)
    public var metadata: MediaMetadata?

    @Relationship(deleteRule: .cascade, inverse: \WatchState.mediaItem)
    public var watchState: WatchState?

    // MARK: Dates

    public var addedAt: Date = Date()
    public var lastModified: Date?

    // MARK: Init

    public init(url: URL, bookmarkData: Data? = nil) {
        self.urlString   = url.absoluteString
        self.bookmarkData = bookmarkData
        self._resolvedURL = url
        self.fileExtension = url.pathExtension.lowercased()
        self.sourceType    = url.isFileURL ? .local : .http
    }

    // MARK: URL Resolution

    /// Returns the URL for this item.
    /// For local files with a bookmark, resolves the security-scoped bookmark.
    @discardableResult
    public func resolveURL() -> URL? {
        if let cached = _resolvedURL { return cached }

        if let bookmark = bookmarkData {
            var isStale = false
            let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            _resolvedURL = url
            return url
        }

        let url = URL(string: urlString)
        _resolvedURL = url
        return url
    }

    public var url: URL? { resolveURL() }

    public func startAccessing() -> Bool {
        url?.startAccessingSecurityScopedResource() ?? false
    }

    public func stopAccessing() {
        url?.stopAccessingSecurityScopedResource()
    }

    // MARK: Display

    public var displayTitle: String {
        metadata?.title ?? url?.deletingPathExtension().lastPathComponent ?? urlString
    }

    public var isWatched: Bool { watchState?.isWatched ?? false }
    public var resumePosition: Double { watchState?.position ?? 0 }
}

// MARK: - Supported Extensions

extension MediaItem {
    public static let supportedExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "avi", "wmv", "flv", "webm",
        "ts",  "m2ts", "mts", "mpg", "mpeg", "m2v", "vob",
        "ogv", "3gp",  "3g2", "divx", "xvid", "rmvb", "rm",
        "iso", "img",                               // disc images
        "mp3", "flac", "aac", "m4a", "ogg", "wav", // audio
        "opus", "wma", "aiff", "alac",
    ]

    public static func isSupported(extension ext: String) -> Bool {
        supportedExtensions.contains(ext.lowercased())
    }
}
