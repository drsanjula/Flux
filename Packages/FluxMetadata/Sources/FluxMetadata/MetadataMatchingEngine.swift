import Foundation
import FluxLibrary

// MARK: - ParsedFilename

/// Result of parsing a media filename.
struct ParsedFilename: Sendable {
    let title: String
    let year: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let mediaType: MediaType
}

// MARK: - MetadataCandidate

public struct MetadataCandidate: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let year: Int?
    public let overview: String
    public let posterPath: String?
    public let tmdbID: Int
    public let mediaType: MediaType
    public let confidence: Double  // 0–1
}

// MARK: - MetadataMatchingEngine

/// Matches media files to TMDb entries using filename parsing + candidate scoring.
///
/// Matching algorithm:
/// 1. Parse filename with regex to extract title, year, season/episode
/// 2. Search TMDb with parsed title (and year if found)
/// 3. Score each candidate: title similarity + year proximity
/// 4. Auto-select if top candidate confidence > 0.85
/// 5. Return all candidates for user disambiguation otherwise
public actor MetadataMatchingEngine {

    private let tmdb: TMDbClient

    public init(tmdb: TMDbClient = TMDbClient()) {
        self.tmdb = tmdb
    }

    // MARK: Public

    /// Attempts to match a filename to TMDb metadata.
    /// Returns ranked candidates; auto-selects if confidence > 0.85.
    public func match(
        filename: String,
        autoSelectThreshold: Double = 0.85
    ) async throws -> (best: MetadataCandidate?, all: [MetadataCandidate]) {
        let parsed = parse(filename: filename)

        let candidates: [MetadataCandidate]
        switch parsed.mediaType {
        case .tvEpisode, .tvShow:
            candidates = try await searchTV(parsed: parsed)
        default:
            candidates = try await searchMovies(parsed: parsed)
        }

        let ranked = candidates.sorted { $0.confidence > $1.confidence }
        let best = ranked.first.flatMap { $0.confidence >= autoSelectThreshold ? $0 : nil }

        return (best: best, all: ranked)
    }

    // MARK: Filename Parsing

    func parse(filename: String) -> ParsedFilename {
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent

        // TV episode: ShowName.S01E03 or ShowName.1x03
        if let (title, season, episode) = extractTVPattern(base) {
            return ParsedFilename(
                title: title, year: nil,
                seasonNumber: season, episodeNumber: episode,
                mediaType: .tvEpisode
            )
        }

        // Movie with year: Movie.Name.2023 or Movie Name (2023)
        if let (title, year) = extractMovieWithYear(base) {
            return ParsedFilename(
                title: title, year: year,
                seasonNumber: nil, episodeNumber: nil,
                mediaType: .movie
            )
        }

        // Plain title
        let cleaned = cleanTitle(base)
        return ParsedFilename(
            title: cleaned, year: nil,
            seasonNumber: nil, episodeNumber: nil,
            mediaType: .movie
        )
    }

    // MARK: Private — Search

    private func searchMovies(parsed: ParsedFilename) async throws -> [MetadataCandidate] {
        let results = try await tmdb.searchMovies(query: parsed.title, year: parsed.year)

        return results.map { movie in
            let movieYear = movie.releaseDate.flatMap { Int($0.prefix(4)) }
            let confidence = score(
                candidateTitle: movie.title,
                queryTitle: parsed.title,
                candidateYear: movieYear,
                queryYear: parsed.year
            )
            return MetadataCandidate(
                id: "movie-\(movie.id)",
                title: movie.title,
                year: movieYear,
                overview: movie.overview,
                posterPath: movie.posterPath,
                tmdbID: movie.id,
                mediaType: .movie,
                confidence: confidence
            )
        }
    }

    private func searchTV(parsed: ParsedFilename) async throws -> [MetadataCandidate] {
        let results = try await tmdb.searchTVShows(query: parsed.title)

        return results.map { show in
            let showYear = show.firstAirDate.flatMap { Int($0.prefix(4)) }
            let confidence = score(
                candidateTitle: show.name,
                queryTitle: parsed.title,
                candidateYear: showYear,
                queryYear: parsed.year
            )
            return MetadataCandidate(
                id: "tv-\(show.id)",
                title: show.name,
                year: showYear,
                overview: show.overview,
                posterPath: show.posterPath,
                tmdbID: show.id,
                mediaType: .tvShow,
                confidence: confidence
            )
        }
    }

    // MARK: Private — Scoring

    /// Scores a candidate against the parsed query.
    /// Score components:
    /// - Title similarity (Levenshtein normalized): 0–0.7
    /// - Year match: +0.3 (exact), +0.15 (off by 1)
    private func score(
        candidateTitle: String,
        queryTitle: String,
        candidateYear: Int?,
        queryYear: Int?
    ) -> Double {
        let titleScore = normalizedLevenshtein(
            a: queryTitle.lowercased(),
            b: candidateTitle.lowercased()
        ) * 0.7

        var yearScore = 0.0
        if let cy = candidateYear, let qy = queryYear {
            let diff = abs(cy - qy)
            if diff == 0      { yearScore = 0.30 }
            else if diff == 1 { yearScore = 0.15 }
        } else if queryYear == nil {
            yearScore = 0.10  // no year in filename — neutral
        }

        return min(1.0, titleScore + yearScore)
    }

    /// Normalized Levenshtein similarity (1 = identical, 0 = completely different).
    private func normalizedLevenshtein(a: String, b: String) -> Double {
        let dist = levenshteinDistance(a: Array(a), b: Array(b))
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1.0 }
        return 1.0 - Double(dist) / Double(maxLen)
    }

    private func levenshteinDistance(a: [Character], b: [Character]) -> Int {
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(0...n)
        for i in 1...m {
            var prev = dp[0]
            dp[0] = i
            for j in 1...n {
                let temp = dp[j]
                dp[j] = a[i-1] == b[j-1]
                    ? prev
                    : 1 + min(prev, min(dp[j], dp[j-1]))
                prev = temp
            }
        }
        return dp[n]
    }

    // MARK: Private — Filename Parsing Helpers

    private func extractTVPattern(_ s: String) -> (title: String, season: Int, episode: Int)? {
        // Match: S01E03, S1E3, 1x03
        let patterns = [
            #"^(.*?)[.\s_-]+[Ss](\d{1,2})[Ee](\d{1,3})"#,
            #"^(.*?)[.\s_-]+(\d{1,2})x(\d{1,3})"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  match.numberOfRanges >= 4
            else { continue }

            let titleRange = Range(match.range(at: 1), in: s)
            let seasonRange = Range(match.range(at: 2), in: s)
            let episodeRange = Range(match.range(at: 3), in: s)

            guard let tr = titleRange, let sr = seasonRange, let er = episodeRange else { continue }
            let title = cleanTitle(String(s[tr]))
            guard let season = Int(s[sr]), let episode = Int(s[er]) else { continue }

            return (title: title, season: season, episode: episode)
        }
        return nil
    }

    private func extractMovieWithYear(_ s: String) -> (title: String, year: Int)? {
        // Match trailing year: (2023) or .2023. or -2023-
        let pattern = #"^(.*?)[\s._\(\[]((?:19|20)\d{2})[\s._\)\]]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              match.numberOfRanges >= 3
        else { return nil }

        guard let titleRange = Range(match.range(at: 1), in: s),
              let yearRange  = Range(match.range(at: 2), in: s) else { return nil }

        let title = cleanTitle(String(s[titleRange]))
        guard let year = Int(s[yearRange]), !title.isEmpty else { return nil }

        return (title: title, year: year)
    }

    /// Removes scene release tags and normalises separators.
    /// "The.Dark.Knight.2008.1080p.BluRay.x264" → "The Dark Knight"
    private func cleanTitle(_ raw: String) -> String {
        let sceneTagsPattern = #"(?i)\b(1080p|720p|4k|2160p|bluray|blu-ray|bdrip|dvdrip|webrip|web-dl|hdtv|x264|x265|h264|h265|hevc|avc|xvid|divx|remux|repack|proper|extended|theatrical|directors|cut|edition|dubbed|multi|ita|eng|fra|ger|hdr|sdr|dv|dolby|atmos|truehd|dts|aac|mp3|flac)\b.*$"#

        var cleaned = raw
        if let regex = try? NSRegularExpression(pattern: sceneTagsPattern) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }

        // Replace separators with spaces
        cleaned = cleaned.replacingOccurrences(of: ".", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "-", with: " ")

        // Collapse whitespace and trim
        let components = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return components.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
