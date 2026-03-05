import SwiftUI
import FluxCore
import FluxLibrary
import FluxUI

// MARK: - RootView

/// Top-level navigation structure for macOS.
/// NavigationSplitView: sidebar (Library/Sources/Settings) + content (poster grid or player).
struct RootView: View {

    // MARK: State

    @State private var session: MediaSession? = try? MediaSession()
    @State private var library = MediaLibrary.shared
    @State private var selectedSidebarItem: SidebarItem = .library
    @State private var selectedItem: MediaItem?
    @State private var isPlayerPresented = false
    @State private var libraryItems: [MediaItem] = []
    @State private var isImporting = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @Environment(\.fluxTheme) private var theme

    // MARK: Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedSidebarItem)
        } detail: {
            detailContent
        }
        .background(theme.colors.backgroundPrimary)
        .sheet(isPresented: $isPlayerPresented) {
            if let session, let item = selectedItem {
                PlayerView(session: session, item: item) {
                    isPlayerPresented = false
                }
                .fluxStyle()
            }
        }
        .onAppear {
            loadLibrary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fluxOpenFile)) { _ in
            openFilePicker(allowDirectories: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .fluxOpenFolder)) { _ in
            openFilePicker(allowDirectories: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .fluxOpenURLs)) { note in
            if let urls = note.userInfo?["urls"] as? [URL] {
                handleOpen(urls: urls)
            }
        }
    }

    // MARK: Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSidebarItem {
        case .library:
            if libraryItems.isEmpty {
                EmptyLibraryView {
                    openFilePicker(allowDirectories: true)
                }
            } else {
                PosterGridView(items: libraryItems) { item in
                    play(item: item)
                }
            }
        case .settings:
            Text("Settings")
                .foregroundStyle(theme.colors.textPrimary)
        }
    }

    // MARK: Playback

    private func play(item: MediaItem) {
        guard let session else { return }
        selectedItem = item
        isPlayerPresented = true

        if let url = item.url {
            item.startAccessing()
            session.open(url: url, startTime: item.resumePosition > 30 ? item.resumePosition : nil)
        }
    }

    // MARK: File Import

    private func openFilePicker(allowDirectories: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = allowDirectories
        panel.canChooseFiles = true
        panel.allowedContentTypes = []   // All files; filtered by extension at scan time

        panel.begin { response in
            guard response == .OK else { return }
            handleOpen(urls: panel.urls)
        }
    }

    private func handleOpen(urls: [URL]) {
        Task {
            let scanner = LibraryScanner()
            for url in urls {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }

                let results = try await scanner.scan(url: url)
                for result in results {
                    _ = library.add(url: result.url, bookmark: result.bookmarkData)
                }
            }
            await MainActor.run { loadLibrary() }
        }
    }

    private func loadLibrary() {
        libraryItems = library.allItems()
    }
}

// MARK: - SidebarItem

enum SidebarItem: String, CaseIterable, Hashable {
    case library  = "Library"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .library:  return "film.stack"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @Binding var selection: SidebarItem
    @Environment(\.fluxTheme) private var theme

    var body: some View {
        List(SidebarItem.allCases, id: \.self, selection: $selection) { item in
            Label(item.rawValue, systemImage: item.icon)
                .foregroundStyle(
                    selection == item ? theme.colors.accent : theme.colors.textPrimary
                )
        }
        .listStyle(.sidebar)
        .background(theme.colors.backgroundSecondary)
        .frame(minWidth: 180)
    }
}

// MARK: - EmptyLibraryView

struct EmptyLibraryView: View {
    let onAddFolder: () -> Void
    @Environment(\.fluxTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.xl) {
            Image(systemName: "film.stack")
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(theme.colors.textTertiary)

            VStack(spacing: theme.spacing.sm) {
                Text("Your library is empty")
                    .font(theme.typography.detailTitle)
                    .foregroundStyle(theme.colors.textPrimary)

                Text("Add a folder of movies or TV shows to get started.")
                    .font(theme.typography.detailBody)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button("Add Folder…", action: onAddFolder)
                .buttonStyle(.borderedProminent)
                .tint(theme.colors.accent)
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.backgroundPrimary)
    }
}

// MARK: - PlayerView

struct PlayerView: View {
    @ObservedObject var session: MediaSession
    let item: MediaItem
    let onClose: () -> Void

    @State private var controlsVisible = true
    @Environment(\.fluxTheme) private var theme

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let client = Optional(session.client) {
                VideoSurfaceView(client: client)
                    .ignoresSafeArea()
            }

            PlayerControlsView(
                session: session,
                isVisible: $controlsVisible,
                onClose: onClose
            )
        }
        .frame(minWidth: 640, minHeight: 360)
        .background(Color.black)
        .onHover { hovering in
            if hovering {
                withAnimation(theme.animations.standard) {
                    controlsVisible = true
                }
            }
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }
}
