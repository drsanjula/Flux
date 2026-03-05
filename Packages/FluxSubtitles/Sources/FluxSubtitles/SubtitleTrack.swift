import Foundation

// MARK: - SubtitleFormat

public enum SubtitleFormat: String, Sendable, CaseIterable {
    case srt  = "srt"
    case ass  = "ass"
    case ssa  = "ssa"
    case vtt  = "vtt"
    case pgs  = "pgs"   // Presentation Graphic Stream (Blu-ray)
    case dvdsub = "dvdsub"
    case unknown = "unknown"

    public static func detect(from url: URL) -> SubtitleFormat {
        SubtitleFormat(rawValue: url.pathExtension.lowercased()) ?? .unknown
    }
}

// MARK: - SubtitleTrack

/// Represents a subtitle track, either embedded in the media container
/// or an external file.
public struct SubtitleTrack: Identifiable, Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        case embedded(trackID: Int)
        case external(url: URL)
        case openSubtitles(id: String, fileID: Int)
    }

    public let id: String
    public let language: String?       // BCP-47 language code (e.g. "en", "fr")
    public let languageName: String    // Human-readable (e.g. "English")
    public let title: String?          // Track title from container
    public let format: SubtitleFormat
    public let source: Source
    public let isForced: Bool
    public let isSDH: Bool             // Subtitles for the Deaf and Hard of hearing

    // MARK: Init — embedded

    public init(
        trackID: Int,
        language: String?,
        title: String?,
        format: SubtitleFormat,
        isForced: Bool = false,
        isSDH: Bool = false
    ) {
        self.id = "embedded-\(trackID)"
        self.language = language
        self.languageName = SubtitleTrack.localizedLanguageName(code: language)
        self.title = title
        self.format = format
        self.source = .embedded(trackID: trackID)
        self.isForced = isForced
        self.isSDH = isSDH
    }

    // MARK: Init — external file

    public init(externalURL url: URL, language: String? = nil) {
        self.id = "external-\(url.absoluteString)"
        self.language = language
        self.languageName = SubtitleTrack.localizedLanguageName(code: language)
        self.title = url.deletingPathExtension().lastPathComponent
        self.format = SubtitleFormat.detect(from: url)
        self.source = .external(url: url)
        self.isForced = false
        self.isSDH = false
    }

    // MARK: Display

    public var displayName: String {
        var parts: [String] = []
        parts.append(languageName)
        if let title, !title.isEmpty { parts.append("(\(title))") }
        if isForced { parts.append("[Forced]") }
        if isSDH    { parts.append("[SDH]") }
        return parts.joined(separator: " ")
    }

    private static func localizedLanguageName(code: String?) -> String {
        guard let code else { return "Unknown" }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}

// MARK: - External Subtitle Finder

/// Finds external subtitle files adjacent to a media file.
/// Matches by filename prefix, e.g., "Movie.en.srt" for "Movie.mkv".
public enum ExternalSubtitleFinder {

    public static let supportedExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "idx"]

    public static func findSubtitles(adjacentTo mediaURL: URL) -> [SubtitleTrack] {
        let dir = mediaURL.deletingLastPathComponent()
        let baseName = mediaURL.deletingPathExtension().lastPathComponent

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return contents
            .filter { url in
                supportedExtensions.contains(url.pathExtension.lowercased())
                && url.lastPathComponent.hasPrefix(baseName)
            }
            .map { url in
                // Extract language code from filename: "Movie.en.srt" → "en"
                let suffix = url.deletingPathExtension().lastPathComponent
                    .dropFirst(baseName.count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
                let lang = suffix.isEmpty ? nil : suffix

                return SubtitleTrack(externalURL: url, language: lang)
            }
            .sorted { $0.displayName < $1.displayName }
    }
}
