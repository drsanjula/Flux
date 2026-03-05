import Foundation
#if canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#endif

// MARK: - ImageSize

public enum ArtworkSize: String, Sendable {
    case thumbnail = "w185"
    case poster    = "w500"
    case backdrop  = "w1280"
    case original  = "original"

    var pixelSize: CGSize {
        switch self {
        case .thumbnail: return CGSize(width: 185, height: 278)
        case .poster:    return CGSize(width: 500, height: 750)
        case .backdrop:  return CGSize(width: 1280, height: 720)
        case .original:  return CGSize(width: 1920, height: 1080)
        }
    }
}

// MARK: - ArtworkCache

/// Two-tier image cache: in-memory NSCache + on-disk persistent cache.
///
/// Images are keyed by TMDb path + size. Disk cache entries expire after 7 days.
/// In-memory cache holds up to 100 images (auto-evicted under memory pressure).
public actor ArtworkCache {

    // MARK: Properties

    public static let shared = ArtworkCache()

    private let memoryCache = NSCache<NSString, AnyObject>()
    private let diskCacheURL: URL
    private let session: URLSession
    private var inFlight: [String: Task<PlatformImage?, Never>] = [:]

    private static let tmdbBaseURL = "https://image.tmdb.org/t/p"
    private static let diskTTL: TimeInterval = 7 * 24 * 60 * 60  // 7 days

    // MARK: Init

    private init() {
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 100 * 1024 * 1024  // 100MB

        let appSupport = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!
        diskCacheURL = appSupport.appendingPathComponent("dev.flux.Flux/Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
        self.session = URLSession(configuration: config)
    }

    // MARK: Public

    /// Fetch an image for a TMDb path at the given size.
    /// Returns cached image if available, otherwise downloads.
    public func image(tmdbPath: String, size: ArtworkSize = .poster) async -> PlatformImage? {
        guard !tmdbPath.isEmpty else { return nil }

        let key = "\(size.rawValue)\(tmdbPath)"
        let nsKey = key as NSString

        // 1. Memory cache
        if let cached = memoryCache.object(forKey: nsKey) as? PlatformImage {
            return cached
        }

        // 2. Coalesce concurrent requests for the same key
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<PlatformImage?, Never> {
            // 3. Disk cache
            if let diskImage = self.loadFromDisk(key: key) {
                self.memoryCache.setObject(diskImage as AnyObject, forKey: nsKey)
                return diskImage
            }

            // 4. Network download
            guard let url = URL(string: "\(Self.tmdbBaseURL)/\(size.rawValue)\(tmdbPath)") else {
                return nil
            }

            do {
                let (data, response) = try await self.session.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                guard let image = PlatformImage(data: data) else { return nil }

                self.saveToDisk(data: data, key: key)
                self.memoryCache.setObject(image as AnyObject, forKey: nsKey)
                return image
            } catch {
                return nil
            }
        }

        inFlight[key] = task
        let result = await task.value
        inFlight.removeValue(forKey: key)
        return result
    }

    /// Prefetch artwork for a list of TMDb paths in the background.
    public func prefetch(tmdbPaths: [String], size: ArtworkSize = .poster) {
        Task {
            for path in tmdbPaths {
                _ = await image(tmdbPath: path, size: size)
            }
        }
    }

    /// Clear all cached artwork.
    public func clearAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    // MARK: Private — Disk

    private func diskURL(for key: String) -> URL {
        let safe = key.replacing(/[^a-zA-Z0-9_-]/, with: "_")
        return diskCacheURL.appendingPathComponent(safe)
    }

    private func loadFromDisk(key: String) -> PlatformImage? {
        let url = diskURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        // Check TTL
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let modified = attrs?[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > Self.diskTTL {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        guard let data = try? Data(contentsOf: url) else { return nil }
        return PlatformImage(data: data)
    }

    private func saveToDisk(data: Data, key: String) {
        let url = diskURL(for: key)
        try? data.write(to: url, options: .atomic)
    }
}
