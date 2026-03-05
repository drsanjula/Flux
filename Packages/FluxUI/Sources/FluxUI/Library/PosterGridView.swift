import SwiftUI
import FluxLibrary
import FluxMetadata

// MARK: - PosterGridView

/// Infuse-style poster grid. Displays MediaItem collection with artwork,
/// title, HDR/DV badges, and watch progress indicators.
public struct PosterGridView: View {

    // MARK: Properties

    let items: [MediaItem]
    let onSelect: (MediaItem) -> Void
    let onLongPress: ((MediaItem) -> Void)?

    @Environment(\.fluxTheme) private var theme
    @State private var hoveredID: UUID?

    // Adaptive column layout: min 140pt poster width
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 12)]

    // MARK: Init

    public init(
        items: [MediaItem],
        onSelect: @escaping (MediaItem) -> Void,
        onLongPress: ((MediaItem) -> Void)? = nil
    ) {
        self.items = items
        self.onSelect = onSelect
        self.onLongPress = onLongPress
    }

    // MARK: Body

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: theme.spacing.posterSpacing) {
                ForEach(items) { item in
                    PosterCell(
                        item: item,
                        isHovered: hoveredID == item.id,
                        onSelect: { onSelect(item) }
                    )
                    .onHover { hovering in
                        withAnimation(theme.animations.hover) {
                            hoveredID = hovering ? item.id : nil
                        }
                    }
                    .contextMenu {
                        posterContextMenu(for: item)
                    }
                }
            }
            .padding(theme.spacing.lg)
        }
        .background(theme.colors.backgroundPrimary)
    }

    @ViewBuilder
    private func posterContextMenu(for item: MediaItem) -> some View {
        Button("Play") { onSelect(item) }
        Divider()
        if item.isWatched {
            Button("Mark as Unwatched") {
                MediaLibrary.shared.markUnwatched(item)
            }
        } else {
            Button("Mark as Watched") {
                MediaLibrary.shared.markWatched(item)
            }
        }
        Divider()
        Button("Remove from Library", role: .destructive) {
            MediaLibrary.shared.remove(item)
        }
    }
}

// MARK: - PosterCell

public struct PosterCell: View {

    let item: MediaItem
    let isHovered: Bool
    let onSelect: () -> Void

    @Environment(\.fluxTheme) private var theme
    @State private var artwork: Image?
    @State private var artworkLoaded = false

    private var posterPath: String? { item.metadata?.posterPath }
    private var displayTitle: String { item.displayTitle }
    private var year: String? {
        guard let y = item.metadata?.releaseYear, y > 0 else { return nil }
        return String(y)
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                posterImage
                    .clipShape(RoundedRectangle(cornerRadius: theme.spacing.posterCornerRadius))
                    .scaleEffect(isHovered ? 1.03 : 1.0)
                    .shadow(color: .black.opacity(isHovered ? 0.5 : 0.25),
                            radius: isHovered ? 12 : 4, y: isHovered ? 6 : 2)
                    .animation(theme.animations.hover, value: isHovered)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(theme.typography.posterTitle)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let year {
                        Text(year)
                            .font(theme.typography.posterSubtitle)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: posterPath) {
            await loadArtwork()
        }
    }

    // MARK: Poster Image

    @ViewBuilder
    private var posterImage: some View {
        GeometryReader { geo in
            ZStack {
                // Background placeholder
                RoundedRectangle(cornerRadius: theme.spacing.posterCornerRadius)
                    .fill(theme.colors.surfaceCard)

                if let artwork {
                    artwork
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity.animation(theme.animations.standard))
                } else {
                    placeholderIcon
                }

                // Overlays
                VStack {
                    HStack {
                        Spacer()
                        badgeStack
                    }
                    Spacer()
                    if item.watchState?.hasProgress == true {
                        progressBar
                    }
                }
                .padding(6)

                if item.isWatched {
                    watchedOverlay
                }
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
    }

    @ViewBuilder
    private var placeholderIcon: some View {
        VStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(theme.colors.textTertiary)
            Text(displayTitle)
                .font(theme.typography.posterSubtitle)
                .foregroundStyle(theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private var badgeStack: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if item.isDolbyVision {
                Badge("DV", color: theme.colors.dolbyVisionBadge)
            } else if item.isHDR {
                Badge("HDR", color: theme.colors.hdrBadge)
            }
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        let progress = item.watchState?.progress ?? 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 3)
                Capsule()
                    .fill(theme.colors.accent)
                    .frame(width: geo.size.width * progress, height: 3)
            }
        }
        .frame(height: 3)
    }

    @ViewBuilder
    private var watchedOverlay: some View {
        ZStack {
            theme.colors.watchedOverlay
                .clipShape(RoundedRectangle(cornerRadius: theme.spacing.posterCornerRadius))
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
        }
    }

    // MARK: Artwork Loading

    private func loadArtwork() async {
        guard let path = posterPath else { return }
        guard let img = await ArtworkCache.shared.image(tmdbPath: path, size: .poster) else { return }
        #if canImport(AppKit)
        artwork = Image(nsImage: img)
        #elseif canImport(UIKit)
        artwork = Image(uiImage: img)
        #endif
    }
}

// MARK: - Badge

struct Badge: View {
    let text: String
    let color: Color

    @Environment(\.fluxTheme) private var theme

    init(_ text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(theme.typography.posterBadge)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
