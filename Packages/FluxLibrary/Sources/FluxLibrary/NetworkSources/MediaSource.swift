import Foundation

// MARK: - SourceItem

/// A browsable item from a network source (file or directory).
public struct SourceItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let isDirectory: Bool
    public let url: URL?          // playback URL (nil for directories)
    public let thumbnailURL: URL? // remote thumbnail
    public let duration: Double?
    public let size: Int64?
    public let modifiedAt: Date?

    public init(
        id: String,
        name: String,
        isDirectory: Bool,
        url: URL? = nil,
        thumbnailURL: URL? = nil,
        duration: Double? = nil,
        size: Int64? = nil,
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

// MARK: - MediaSource

/// Protocol for all network sources: SMB, WebDAV, Plex, Jellyfin, Emby.
public protocol MediaSource: AnyObject, Sendable {
    var id: String { get }
    var name: String { get }
    var isConnected: Bool { get }

    func connect() async throws
    func disconnect() async

    /// List contents of a directory. Pass nil for root.
    func list(path: String?) async throws -> [SourceItem]

    /// Search items by name.
    func search(query: String) async throws -> [SourceItem]

    /// Resolve a playback URL (may add auth headers, redirect, etc.).
    func resolvePlaybackURL(for item: SourceItem) async throws -> URL
}

// MARK: - SMBSource

/// Browses SMB network shares using macOS native SMB client.
/// The `smb://` URL scheme is handled by macOS's built-in SMB stack.
public final class SMBSource: MediaSource {
    public let id: String
    public let name: String
    public let host: String
    public let share: String
    private let credential: URLCredential?
    private(set) public var isConnected: Bool = false

    public init(host: String, share: String, name: String? = nil, credential: URLCredential? = nil) {
        self.host = host
        self.share = share
        self.name = name ?? "\\\\\(host)\\\(share)"
        self.id = "smb://\(host)/\(share)"
        self.credential = credential
    }

    public func connect() async throws {
        // macOS mounts SMB shares via the smb:// URL scheme automatically
        // when accessed through FileManager. No explicit connection needed.
        isConnected = true
    }

    public func disconnect() async {
        isConnected = false
    }

    public func list(path: String?) async throws -> [SourceItem] {
        let baseURL = URL(string: "smb://\(host)/\(share)")!
        let dirURL = path.map { baseURL.appendingPathComponent($0) } ?? baseURL

        let contents = try FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        )

        return contents.compactMap { url in
            let resources = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            let isDir = resources?.isDirectory ?? false

            if !isDir && !MediaItem.isSupported(extension: url.pathExtension) {
                return nil
            }

            return SourceItem(
                id: url.absoluteString,
                name: url.lastPathComponent,
                isDirectory: isDir,
                url: isDir ? nil : url,
                size: resources?.fileSize.map { Int64($0) },
                modifiedAt: resources?.contentModificationDate
            )
        }
        .sorted { $0.isDirectory && !$1.isDirectory || $0.name < $1.name }
    }

    public func search(query: String) async throws -> [SourceItem] {
        // SMB doesn't have native search — traverse root and filter
        let root = try await list(path: nil)
        return root.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    public func resolvePlaybackURL(for item: SourceItem) async throws -> URL {
        guard let url = item.url else {
            throw URLError(.badURL)
        }
        return url
    }
}

// MARK: - WebDAVSource

public final class WebDAVSource: MediaSource {
    public let id: String
    public let name: String
    public let baseURL: URL
    private let session: URLSession
    private(set) public var isConnected: Bool = false

    public init(baseURL: URL, name: String, credential: URLCredential? = nil) {
        self.baseURL = baseURL
        self.name = name
        self.id = baseURL.absoluteString

        let config = URLSessionConfiguration.default
        if let cred = credential {
            let storage = URLCredentialStorage.shared
            storage.setDefaultCredential(cred, for: URLProtectionSpace(
                host: baseURL.host ?? "",
                port: baseURL.port ?? (baseURL.scheme == "https" ? 443 : 80),
                protocol: baseURL.scheme,
                realm: nil,
                authenticationMethod: NSURLAuthenticationMethodHTTPBasic
            ))
        }
        self.session = URLSession(configuration: config)
    }

    public func connect() async throws {
        // Test connectivity with a PROPFIND request
        var request = URLRequest(url: baseURL)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 207 else {
            throw URLError(.badServerResponse)
        }
        isConnected = true
    }

    public func disconnect() async {
        isConnected = false
    }

    public func list(path: String?) async throws -> [SourceItem] {
        let url = path.map { baseURL.appendingPathComponent($0) } ?? baseURL
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        let body = """
        <?xml version="1.0"?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:displayname/><d:resourcetype/><d:getcontentlength/>
            <d:getlastmodified/><d:getcontenttype/>
          </d:prop>
        </d:propfind>
        """
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await session.data(for: request)
        return parseWebDAVResponse(data, baseURL: url)
    }

    public func search(query: String) async throws -> [SourceItem] {
        // WebDAV SEARCH not universally supported — traverse root
        let items = try await list(path: nil)
        return items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    public func resolvePlaybackURL(for item: SourceItem) async throws -> URL {
        guard let url = item.url else { throw URLError(.badURL) }
        return url
    }

    private func parseWebDAVResponse(_ data: Data, baseURL: URL) -> [SourceItem] {
        // Minimal XML parsing — production implementation would use XMLParser
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var items: [SourceItem] = []
        let responses = xml.components(separatedBy: "<d:response>").dropFirst()
        for response in responses {
            guard let hrefRange = response.range(of: "<d:href>"),
                  let hrefEndRange = response.range(of: "</d:href>") else { continue }
            let href = String(response[hrefRange.upperBound..<hrefEndRange.lowerBound])
            guard let itemURL = URL(string: href, relativeTo: baseURL)?.absoluteURL else { continue }

            let isDir = response.contains("<d:collection/>")
            let name = itemURL.lastPathComponent
            guard !name.isEmpty, name != "." else { continue }

            if !isDir && !MediaItem.isSupported(extension: itemURL.pathExtension) { continue }

            items.append(SourceItem(
                id: itemURL.absoluteString,
                name: name,
                isDirectory: isDir,
                url: isDir ? nil : itemURL
            ))
        }
        return items
    }
}
