import Foundation
import AVFoundation
import UniformTypeIdentifiers

// MARK: - ScanResult

public struct ScanResult: Sendable {
    public let url: URL
    public let bookmarkData: Data?
    public let fileSizeBytes: Int64
    public let modifiedAt: Date?
    public let durationSeconds: Double
    public let isHDR: Bool
    public let isDolbyVision: Bool
}

// MARK: - ScanProgress

public struct ScanProgress: Sendable {
    public let scanned: Int
    public let found: Int
    public let currentFile: String
}

// MARK: - LibraryScanner

/// Scans directories for media files and creates MediaItem records.
///
/// Runs on a background actor. Uses `FileManager.enumerator` to walk
/// directory trees. Probes each file with lightweight `AVAsset` inspection
/// to detect HDR/DV metadata without full decode.
public actor LibraryScanner {

    // MARK: State

    private(set) public var isScanning: Bool = false

    // MARK: Scan

    /// Scans `url` (file or directory) and yields results.
    /// Caller must have a security-scoped access grant for `url`.
    public func scan(
        url: URL,
        progressHandler: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> [ScanResult] {
        isScanning = true
        defer { isScanning = false }

        var results: [ScanResult] = []
        var scanned = 0

        if url.hasDirectoryPath {
            let urls = try enumerateMediaFiles(in: url)
            for fileURL in urls {
                scanned += 1
                progressHandler?(ScanProgress(
                    scanned: scanned,
                    found: results.count,
                    currentFile: fileURL.lastPathComponent
                ))
                if let result = await probe(fileURL) {
                    results.append(result)
                }
                // Yield to prevent blocking the event loop
                if scanned % 10 == 0 {
                    await Task.yield()
                }
            }
        } else if let result = await probe(url) {
            results.append(result)
        }

        return results
    }

    // MARK: Private

    private func enumerateMediaFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .isHiddenKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let resources = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey])
            guard resources?.isRegularFile == true, resources?.isHidden != true else { continue }
            guard MediaItem.isSupported(extension: url.pathExtension) else { continue }
            urls.append(url)
        }
        return urls
    }

    private func probe(_ url: URL) async -> ScanResult? {
        let resources = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize  = Int64(resources?.fileSize ?? 0)
        let modified  = resources?.contentModificationDate

        // Create security-scoped bookmark for sandbox access
        let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        // Probe with AVAsset for duration and HDR/DV info
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])

        var duration: Double = 0
        var isHDR = false
        var isDolbyVision = false

        do {
            let avDuration = try await asset.load(.duration)
            duration = avDuration.seconds

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if let track = videoTracks.first {
                let fmts = try await track.load(.formatDescriptions)
                for fmt in fmts {
                    let desc = fmt as CMFormatDescription
                    let hdrInfo = detectHDR(desc)
                    isHDR = hdrInfo.isHDR
                    isDolbyVision = hdrInfo.isDolbyVision
                }
            }
        } catch {
            // Non-fatal: file might not be parseable by AVFoundation
            // mpv will handle it at playback time
        }

        return ScanResult(
            url: url,
            bookmarkData: bookmark,
            fileSizeBytes: fileSize,
            modifiedAt: modified,
            durationSeconds: duration,
            isHDR: isHDR,
            isDolbyVision: isDolbyVision
        )
    }

    private func detectHDR(_ desc: CMFormatDescription) -> (isHDR: Bool, isDolbyVision: Bool) {
        let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any] ?? [:]

        // Dolby Vision
        if extensions["DOVIConfigurationBox"] != nil {
            return (true, true)
        }

        let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
        let pq = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
        let hlg = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String

        if transfer == pq || transfer == hlg {
            return (true, false)
        }

        return (false, false)
    }
}
