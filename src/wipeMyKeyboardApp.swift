import SwiftUI

@main
struct wipeMyKeyboardApp: App {
    @StateObject private var locker = KeyboardLocker()

    var body: some Scene {
        MenuBarExtra("Wipe My Keyboard", systemImage: "keyboard") {
            ContentView(locker: locker)
        }
        .menuBarExtraStyle(.window)
    }
}
