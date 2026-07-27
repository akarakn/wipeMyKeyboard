import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var locker: KeyboardLocker
    @State private var isRecordingShortcut = false
    @State private var shortcutMonitor: Any?
    
    var body: some View {
        VStack(spacing: 20) {
            if !locker.isAccessibilityEnabled && !locker.isLocked {
                Text("Accessibility Permissions Required")
                    .foregroundColor(.red)
                    .font(.headline)
                Text("from System Settings > Privacy & Security > Accessibility.")
                    .multilineTextAlignment(.center)
                    .font(.caption)
                    .padding(.horizontal)
            }
            
            if locker.isLocked {
                Text("Keyboard Locked")
                    .font(.largeTitle)
                    .bold()
                
                Text("\(locker.timeRemaining)s")
                    .font(.system(size: 60, weight: .bold, design: .monospaced))
                    .foregroundColor(locker.timeRemaining <= 5 ? .red : .primary)
                
                VStack(spacing: 8) {
                    Button("Unlock") {
                        locker.stopLocking()
                    }

                    Text("or press \(locker.unlockShortcutDescription)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Wipe My Keyboard")
                    .font(.title)
                    .bold()
                
                VStack {
                    Text("Duration: \(Int(locker.duration)) seconds")
                    Slider(value: $locker.duration, in: 10...120, step: 10)
                        .padding(.horizontal)
                }

                VStack(spacing: 6) {
                    Text("Unlock Shortcut")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        isRecordingShortcut
                            ? stopShortcutRecording()
                            : startShortcutRecording()
                    } label: {
                        Text(
                            isRecordingShortcut
                                ? "Press a shortcut…"
                                : locker.unlockShortcutDescription
                        )
                        .frame(minWidth: 130)
                    }

                    if isRecordingShortcut {
                        Text("Press one modifier and one key")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: {
                    locker.startLocking()
                }) {
                    Text("Lock Keyboard")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
            }
        }
        .padding()
        .frame(width: 300, height: 320)
        .onDisappear {
            stopShortcutRecording()
        }
    }

    private func startShortcutRecording() {
        stopShortcutRecording()
        isRecordingShortcut = true

        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard
                let modifier = shortcutModifier(from: event.modifierFlags),
                let keyName = shortcutKeyName(for: event)
            else {
                NSSound.beep()
                return nil
            }

            locker.updateUnlockShortcut(
                keyCode: Int64(event.keyCode),
                modifier: modifier,
                keyName: keyName
            )

            DispatchQueue.main.async {
                stopShortcutRecording()
            }

            return nil
        }
    }

    private func stopShortcutRecording() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }

        isRecordingShortcut = false
    }

    private func shortcutModifier(
        from flags: NSEvent.ModifierFlags
    ) -> CGEventFlags? {
        let activeModifiers: [CGEventFlags] = [
            flags.contains(.command) ? .maskCommand : nil,
            flags.contains(.option) ? .maskAlternate : nil,
            flags.contains(.control) ? .maskControl : nil,
            flags.contains(.shift) ? .maskShift : nil
        ].compactMap { $0 }

        guard activeModifiers.count == 1 else { return nil }
        return activeModifiers[0]
    }

    private func shortcutKeyName(for event: NSEvent) -> String? {
        let namedKeys: [UInt16: String] = [
            36: "Return",
            48: "Tab",
            49: "Space",
            51: "Delete",
            53: "Esc",
            123: "←",
            124: "→",
            125: "↓",
            126: "↑"
        ]

        if let name = namedKeys[event.keyCode] {
            return name
        }

        guard
            let characters = event.charactersIgnoringModifiers?.uppercased(),
            characters.count == 1,
            characters.first?.isASCII == true,
            characters.first?.isWhitespace == false
        else {
            return nil
        }

        return characters
    }
}
