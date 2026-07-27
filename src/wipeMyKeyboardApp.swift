import AppKit
import SwiftUI

@main
struct wipeMyKeyboardApp: App {
    @StateObject private var locker = KeyboardLocker()

    var body: some Scene {
        MenuBarExtra {
            ContentView(locker: locker)
        } label: {
            if locker.isLocked {
                Image(nsImage: lockedMenuBarIcon)
            } else {
                Image(systemName: "keyboard")
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var lockedMenuBarIcon: NSImage {
        let image = NSImage(
            systemSymbolName: "lock.fill",
            accessibilityDescription: "Keyboard locked"
        ) ?? NSImage()

        let configuration = NSImage.SymbolConfiguration(
            paletteColors: [.systemRed]
        )
        let configuredImage = image.withSymbolConfiguration(configuration) ?? image
        configuredImage.isTemplate = false

        return configuredImage
    }
}
