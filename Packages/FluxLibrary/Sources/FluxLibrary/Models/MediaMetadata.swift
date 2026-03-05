import Foundation
import SwiftData

// MARK: - Media Type

public enum MediaType: String, Codable, Sendable, CaseIterable {
    case movie
    case tvShow
    case tvEpisode
    case music
    case unknown
}

// MARK: - Genre

public struct Genre: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
}

// MARK: - CastMember

public struct CastMember: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let character: String?
    public let profilePath: String?  // relative path for TMDb image API
}

// MARK: - MediaMetadata

/// Metadata fetched from TMDb, TVDB, or MusicBrainz.
/// Stored separately from MediaItem to allow re-fetching without losing playback state.
@Model
public final class MediaMetadata {

    @Attribute(.unique)
    public var id: UUID = UUID()

    // MARK: Relationship

    public var mediaItem: MediaItem?

    // MARK: Classification

    public var mediaType: MediaType = .unknown

    // MARK: Core Metadata

    public var title: String = ""
    public var originalTitle: String = ""
    public var overview: String = ""
    public var tagline: String = ""
    public var releaseYear: Int = 0
    public var releaseDate: String = ""    // ISO8601 date string
    public var runtimeMinutes: Int = 0

    // MARK: External IDs

    public var tmdbID: Int = 0
    public var tvdbID: Int = 0
    public var imdbID: String = ""

    // MARK: TV-Specific

    public var showTitle: String = ""
    public var seasonNumber: Int = 0
    public var episodeNumber: Int = 0

    // MARK: Artwork URLs (relative paths for TMDb CDN)

    public var posterPath: String = ""
    public var backdropPath: String = ""
    public var thumbnailPath: String = ""  // episode thumbnail

    // Cached full URLs (computed from CDN base)
    @Transient
    public var posterURL: URL? { tmdbImageURL(path: posterPath, size: "w500") }
    @Transient
    public var backdropURL: URL? { tmdbImageURL(path: backdropPath, size: "w1280") }
    @Transient
    public var thumbnailURL: URL? { tmdbImageURL(path: thumbnailPath, size: "w300") }

    // MARK: Ratings

    public var tmdbRating: Double = 0      // 0–10
    public var tmdbVoteCount: Int = 0
    public var userRating: Int = 0         // 1–5 stars (0 = unrated)

    // MARK: Genres / Cast (stored as JSON)

    private var genresData: Data = Data()
    private var castData: Data = Data()

    public var genres: [Genre] {
        get { (try? JSONDecoder().decode([Genre].self, from: genresData)) ?? [] }
        set { genresData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    public var cast: [CastMember] {
        get { (try? JSONDecoder().decode([CastMember].self, from: castData)) ?? [] }
        set { castData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    public var director: String = ""
    public var studio: String = ""
    public var contentRating: String = ""  // "PG-13", "TV-MA", etc.

    // MARK: Source

    public var fetchedAt: Date = Date()
    public var fetchedFrom: String = ""    // "tmdb", "tvdb", "musicbrainz"

    // MARK: Init

    public init() {}

    public init(mediaType: MediaType, title: String, tmdbID: Int = 0) {
        self.mediaType = mediaType
        self.title     = title
        self.tmdbID    = tmdbID
    }

    // MARK: Helpers

    private func tmdbImageURL(path: String, size: String) -> URL? {
        guard !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    public var displayTitle: String {
        if mediaType == .tvEpisode && !showTitle.isEmpty {
            let epStr = "S\(String(format: "%02d", seasonNumber))E\(String(format: "%02d", episodeNumber))"
            return "\(showTitle) — \(epStr) \(title)"
        }
        return title
    }
}
