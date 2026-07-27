import Foundation
import Cocoa
import CoreGraphics
import Combine

class KeyboardLocker: ObservableObject {
    static let infiniteDurationValue = 130.0

    @Published var isLocked: Bool = false
    @Published var timeRemaining: Int = 0
    @Published var duration: Double = 30.0

    @Published private(set) var unlockKeyCode: Int64
    @Published private(set) var unlockModifier: CGEventFlags
    @Published private(set) var unlockKeyName: String

    private static let defaultUnlockKeyCode: Int64 = 53
    private static let defaultUnlockModifier: CGEventFlags = .maskControl
    private static let defaultUnlockKeyName = "Esc"
    private static let supportedModifierFlags: CGEventFlags = [
        .maskCommand,
        .maskAlternate,
        .maskControl,
        .maskShift
    ]

    private enum DefaultsKey {
        static let unlockKeyCode = "unlockKeyCode"
        static let unlockModifier = "unlockModifier"
        static let unlockKeyName = "unlockKeyName"
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: AnyCancellable?

    init() {
        let defaults = UserDefaults.standard

        self.unlockKeyCode = defaults.object(forKey: DefaultsKey.unlockKeyCode) == nil
            ? Self.defaultUnlockKeyCode
            : Int64(defaults.integer(forKey: DefaultsKey.unlockKeyCode))

        self.unlockModifier = defaults.object(forKey: DefaultsKey.unlockModifier) == nil
            ? Self.defaultUnlockModifier
            : CGEventFlags(
                rawValue: UInt64(defaults.integer(forKey: DefaultsKey.unlockModifier))
            )

        self.unlockKeyName = defaults.string(forKey: DefaultsKey.unlockKeyName)
            ?? Self.defaultUnlockKeyName
    }

    var unlockShortcutDescription: String {
        "\(Self.modifierName(for: unlockModifier)) + \(unlockKeyName)"
    }

    var isInfiniteDuration: Bool {
        duration >= Self.infiniteDurationValue
    }
    
    var isAccessibilityEnabled: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func startLocking() {
        guard isAccessibilityEnabled else { return }
        
        let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return nil }

            let locker = Unmanaged<KeyboardLocker>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            let activeModifiers = event.flags
                .intersection(KeyboardLocker.supportedModifierFlags)
            let isUnlockShortcut =
                type == .keyDown &&
                event.getIntegerValueField(.keyboardEventKeycode) == locker.unlockKeyCode &&
                activeModifiers == locker.unlockModifier

            if isUnlockShortcut {
                DispatchQueue.main.async { locker.stopLocking() }
            }

            return nil
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) | 
                        (1 << CGEventType.keyUp.rawValue) | 
                        (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << 14) // NX_SYSDEFINED for media/function keys
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap")
            return
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), self.runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        self.isLocked = true

        if isInfiniteDuration {
            self.timeRemaining = 0
            return
        }

        self.timeRemaining = Int(self.duration)
        
        self.timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            self.timeRemaining -= 1
            
            if self.timeRemaining <= 5 && self.timeRemaining > 0 {
                NSSound.beep()
            }
            
            if self.timeRemaining <= 0 {
                self.stopLocking(playCompletionSound: true)
            }
        }
    }

    func updateUnlockShortcut(
        keyCode: Int64,
        modifier: CGEventFlags,
        keyName: String
    ) {
        unlockKeyCode = keyCode
        unlockModifier = modifier
        unlockKeyName = keyName

        let defaults = UserDefaults.standard
        defaults.set(keyCode, forKey: DefaultsKey.unlockKeyCode)
        defaults.set(Int(modifier.rawValue), forKey: DefaultsKey.unlockModifier)
        defaults.set(keyName, forKey: DefaultsKey.unlockKeyName)
    }
    
    func stopLocking(playCompletionSound: Bool = false) {
        if let tap = self.eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = self.runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
        
        self.timer?.cancel()
        self.timer = nil
        self.isLocked = false
        self.timeRemaining = 0
        
        if playCompletionSound {
            NSSound(named: "Glass")?.play()
        }
    }

    private static func modifierName(for modifier: CGEventFlags) -> String {
        switch modifier {
        case .maskCommand:
            return "Command"
        case .maskAlternate:
            return "Option"
        case .maskShift:
            return "Shift"
        default:
            return "Control"
        }
    }
}
