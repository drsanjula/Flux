import SwiftUI
import FluxCore
import FluxLibrary
import FluxUI

@main
struct FluxApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .fluxStyle()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 780)
        .commands {
            FluxCommands()
        }
    }
}

// MARK: - Commands

struct FluxCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open File…") {
                NotificationCenter.default.post(name: .fluxOpenFile, object: nil)
            }
            .keyboardShortcut("o")

            Button("Open Folder…") {
                NotificationCenter.default.post(name: .fluxOpenFolder, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }
}

extension Notification.Name {
    static let fluxOpenFile   = Notification.Name("dev.flux.openFile")
    static let fluxOpenFolder = Notification.Name("dev.flux.openFolder")
}
