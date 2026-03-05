import Foundation
import FluxLibrary

// MARK: - TMDb Models

public struct TMDbMovie: Decodable, Sendable {
    public let id: Int
    public let title: String
    public let originalTitle: String
    public let overview: String
    public let releaseDate: String?
    public let runtime: Int?
    public let voteAverage: Double
    public let voteCount: Int
    public let posterPath: String?
    public let backdropPath: String?
    public let tagline: String?
    public let genres: [TMDbGenre]?
    public let productionCompanies: [TMDbCompany]?
    public let credits: TMDbCredits?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime, genres, tagline, credits
        case originalTitle       = "original_title"
        case releaseDate         = "release_date"
        case voteAverage         = "vote_average"
        case voteCount           = "vote_count"
        case posterPath          = "poster_path"
        case backdropPath        = "backdrop_path"
        case productionCompanies = "production_companies"
    }
}

public struct TMDbTVShow: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let overview: String
    public let firstAirDate: String?
    public let voteAverage: Double
    public let voteCount: Int
    public let posterPath: String?
    public let backdropPath: String?
    public let genres: [TMDbGenre]?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, genres
        case firstAirDate = "first_air_date"
        case voteAverage  = "vote_average"
        case voteCount    = "vote_count"
        case posterPath   = "poster_path"
        case backdropPath = "backdrop_path"
    }
}

public struct TMDbTVEpisode: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let overview: String
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let airDate: String?
    public let runtime: Int?
    public let stillPath: String?   // thumbnail
    public let voteAverage: Double

    enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case seasonNumber  = "season_number"
        case episodeNumber = "episode_number"
        case airDate       = "air_date"
        case stillPath     = "still_path"
        case voteAverage   = "vote_average"
    }
}

public struct TMDbGenre: Decodable, Sendable {
    public let id: Int
    public let name: String
}

public struct TMDbCompany: Decodable, Sendable {
    public let id: Int
    public let name: String
}

public struct TMDbCredits: Decodable, Sendable {
    public let cast: [TMDbCastMember]?
    public let crew: [TMDbCrewMember]?
}

public struct TMDbCastMember: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let character: String?
    public let profilePath: String?
    enum CodingKeys: String, CodingKey {
        case id, name, character
        case profilePath = "profile_path"
    }
}

public struct TMDbCrewMember: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let job: String?
    public let profilePath: String?
    enum CodingKeys: String, CodingKey {
        case id, name, job
        case profilePath = "profile_path"
    }
}

public struct TMDbSearchResults<T: Decodable>: Decodable {
    public let results: [T]
    public let totalResults: Int
    public let totalPages: Int
    enum CodingKeys: String, CodingKey {
        case results
        case totalResults = "total_results"
        case totalPages   = "total_pages"
    }
}

// MARK: - TMDb Errors

public enum TMDbError: Error, Sendable {
    case missingAPIKey
    case networkError(Error)
    case invalidResponse
    case notFound
    case rateLimited
}

// MARK: - TMDbClient

/// Client for The Movie Database (TMDb) API v3.
///
/// Requires a commercial API key for commercial use.
/// Contact partnerships@themoviedb.org for commercial licensing.
///
/// Rate limit: 40 requests per 10 seconds.
/// This client respects the limit with a 0.25s delay between requests.
public actor TMDbClient {

    // MARK: Config

    // Set via APIKeyProvider — see APIKeys.swift (not committed to repo)
    public static var apiKey: String = ""

    private static let baseURL = "https://api.themoviedb.org/3"
    private let session: URLSession

    // Simple rate limiter: minimum 250ms between requests
    private var lastRequestTime: Date = .distantPast
    private let minRequestInterval: TimeInterval = 0.25

    // MARK: Init

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: Search

    public func searchMovies(query: String, year: Int? = nil) async throws -> [TMDbMovie] {
        var params = ["query": query, "language": "en-US", "page": "1"]
        if let year { params["year"] = String(year) }

        let results: TMDbSearchResults<TMDbMovie> = try await get(
            path: "/search/movie",
            params: params
        )
        return results.results
    }

    public func searchTVShows(query: String, year: Int? = nil) async throws -> [TMDbTVShow] {
        var params = ["query": query, "language": "en-US", "page": "1"]
        if let year { params["first_air_date_year"] = String(year) }

        let results: TMDbSearchResults<TMDbTVShow> = try await get(
            path: "/search/tv",
            params: params
        )
        return results.results
    }

    // MARK: Details

    public func movieDetails(id: Int) async throws -> TMDbMovie {
        try await get(path: "/movie/\(id)", params: [
            "language": "en-US",
            "append_to_response": "credits",
        ])
    }

    public func tvEpisodeDetails(showID: Int, season: Int, episode: Int) async throws -> TMDbTVEpisode {
        try await get(path: "/tv/\(showID)/season/\(season)/episode/\(episode)", params: [
            "language": "en-US",
        ])
    }

    // MARK: Private

    private func get<T: Decodable>(path: String, params: [String: String]) async throws -> T {
        guard !Self.apiKey.isEmpty else { throw TMDbError.missingAPIKey }

        // Rate limiting
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRequestTime)
        if elapsed < minRequestInterval {
            try await Task.sleep(nanoseconds: UInt64((minRequestInterval - elapsed) * 1_000_000_000))
        }
        lastRequestTime = Date()

        var components = URLComponents(string: Self.baseURL + path)!
        var queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        queryItems.append(URLQueryItem(name: "api_key", value: Self.apiKey))
        components.queryItems = queryItems

        guard let url = components.url else { throw TMDbError.invalidResponse }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw TMDbError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw TMDbError.invalidResponse }

        switch http.statusCode {
        case 200:
            break
        case 404:
            throw TMDbError.notFound
        case 429:
            throw TMDbError.rateLimited
        default:
            throw TMDbError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TMDbError.invalidResponse
        }
    }
}
