import AppKit
import FluxCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Log hardware decoder capabilities at launch
        print(HardwareDecoder.shared)

        // Accept media files dropped onto the dock icon
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        NotificationCenter.default.post(
            name: .fluxOpenURLs,
            object: nil,
            userInfo: ["urls": urls]
        )
    }
}

extension Notification.Name {
    static let fluxOpenURLs = Notification.Name("dev.flux.openURLs")
}
