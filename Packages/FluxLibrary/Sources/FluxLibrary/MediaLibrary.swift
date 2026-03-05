import Foundation
import SwiftData

// MARK: - LibraryFilter

public struct LibraryFilter: Sendable, Equatable {
    public var mediaTypes: Set<MediaType> = []
    public var genres: Set<String> = []
    public var isWatched: Bool? = nil       // nil = show all
    public var isHDR: Bool? = nil
    public var searchText: String = ""
    public var sortOrder: SortOrder = .addedDesc

    public enum SortOrder: String, CaseIterable, Sendable {
        case titleAsc    = "Title A–Z"
        case titleDesc   = "Title Z–A"
        case addedDesc   = "Recently Added"
        case addedAsc    = "Oldest First"
        case yearDesc    = "Newest Release"
        case yearAsc     = "Oldest Release"
        case ratingDesc  = "Highest Rated"
        case lastPlayed  = "Recently Played"
    }

    public init() {}

    public var isEmpty: Bool {
        mediaTypes.isEmpty && genres.isEmpty && isWatched == nil
            && isHDR == nil && searchText.isEmpty
    }
}

// MARK: - MediaLibrary

/// Central data store for all media items.
/// Uses SwiftData as the persistence backend.
@MainActor
public final class MediaLibrary: ObservableObject {

    // MARK: Properties

    private let container: ModelContainer
    private let context: ModelContext

    public static let shared: MediaLibrary = {
        do {
            return try MediaLibrary()
        } catch {
            fatalError("Failed to create MediaLibrary: \(error)")
        }
    }()

    // MARK: Init

    public init() throws {
        let schema = Schema([
            MediaItem.self,
            MediaMetadata.self,
            WatchState.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            url: Self.storeURL,
            allowsSave: true,
            cloudKitDatabase: .automatic  // CloudKit sync for watch state
        )
        self.container = try ModelContainer(for: schema, configurations: config)
        self.context   = container.mainContext
    }

    // MARK: Store URL

    private static var storeURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("dev.flux.Flux", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Library.sqlite")
    }

    // MARK: Queries

    public func allItems(filter: LibraryFilter = LibraryFilter()) -> [MediaItem] {
        var descriptor = FetchDescriptor<MediaItem>()

        var predicates: [Predicate<MediaItem>] = []

        if !filter.searchText.isEmpty {
            let q = filter.searchText
            predicates.append(#Predicate<MediaItem> { item in
                item.urlString.localizedStandardContains(q)
            })
        }

        if let watched = filter.isWatched {
            // Join via relationship — simplified predicate
            // Full implementation would fetch separately and intersect
            _ = watched // TODO: cross-relationship predicate
        }

        if let predicate = predicates.first {
            descriptor.predicate = predicate
        }

        descriptor.sortBy = sortDescriptors(for: filter.sortOrder)

        return (try? context.fetch(descriptor)) ?? []
    }

    public func item(for url: URL) -> MediaItem? {
        let urlStr = url.absoluteString
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.urlString == urlStr }
        )
        return try? context.fetch(descriptor).first
    }

    // MARK: Mutations

    @discardableResult
    public func add(url: URL, bookmark: Data? = nil) -> MediaItem {
        if let existing = item(for: url) { return existing }

        let item = MediaItem(url: url, bookmarkData: bookmark)
        let watchState = WatchState()
        watchState.mediaItem = item
        item.watchState = watchState

        context.insert(item)
        context.insert(watchState)
        save()
        return item
    }

    public func remove(_ item: MediaItem) {
        context.delete(item)
        save()
    }

    public func removeAll(_ items: [MediaItem]) {
        items.forEach { context.delete($0) }
        save()
    }

    // MARK: Watch State

    public func updateWatchState(for item: MediaItem, position: Double, duration: Double) {
        let state = item.watchState ?? {
            let ws = WatchState()
            ws.mediaItem = item
            item.watchState = ws
            context.insert(ws)
            return ws
        }()
        state.update(position: position, duration: duration)
        save()
    }

    public func markWatched(_ item: MediaItem) {
        item.watchState?.markWatched()
        save()
    }

    public func markUnwatched(_ item: MediaItem) {
        item.watchState?.markUnwatched()
        save()
    }

    // MARK: Private

    private func save() {
        try? context.save()
    }

    private func sortDescriptors(for order: LibraryFilter.SortOrder) -> [SortDescriptor<MediaItem>] {
        switch order {
        case .titleAsc:   return [SortDescriptor(\.urlString, order: .forward)]
        case .titleDesc:  return [SortDescriptor(\.urlString, order: .reverse)]
        case .addedDesc:  return [SortDescriptor(\.addedAt, order: .reverse)]
        case .addedAsc:   return [SortDescriptor(\.addedAt, order: .forward)]
        default:          return [SortDescriptor(\.addedAt, order: .reverse)]
        }
    }
}
