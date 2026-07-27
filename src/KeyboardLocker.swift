import Foundation
import Cocoa
import CoreGraphics
import Combine
import Carbon

class KeyboardLocker: ObservableObject {
    static let infiniteDurationValue = 130.0

    @Published var isLocked: Bool = false
    @Published var timeRemaining: Int = 0
    @Published var duration: Double {
        didSet {
            UserDefaults.standard.set(duration, forKey: DefaultsKey.duration)
        }
    }

    @Published private(set) var unlockKeyCode: Int64
    @Published private(set) var unlockModifier: CGEventFlags
    @Published private(set) var unlockKeyName: String
    @Published private(set) var globalShortcutError: String?

    private static let defaultUnlockKeyCode: Int64 = 53
    private static let defaultUnlockModifier: CGEventFlags = .maskControl
    private static let defaultUnlockKeyName = "Esc"
    private static let defaultDuration = 30.0
    private static let minimumDuration = 10.0
    private static let lockHotKeyID = EventHotKeyID(
        signature: OSType(0x574D4B42),
        id: 1
    )
    private static let supportedModifierFlags: CGEventFlags = [
        .maskCommand,
        .maskAlternate,
        .maskControl,
        .maskShift
    ]

    private enum DefaultsKey {
        static let duration = "duration"
        static let unlockKeyCode = "unlockKeyCode"
        static let unlockModifier = "unlockModifier"
        static let unlockKeyName = "unlockKeyName"
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: AnyCancellable?
    private var globalHotKey: EventHotKeyRef?
    private var globalHotKeyHandler: EventHandlerRef?
    private var ignoreUnlockShortcutUntilKeyUp = false

    init() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: DefaultsKey.duration) == nil {
            self.duration = Self.defaultDuration
        } else {
            let savedDuration = defaults.double(forKey: DefaultsKey.duration)
            self.duration = (Self.minimumDuration...Self.infiniteDurationValue)
                .contains(savedDuration)
                ? savedDuration
                : Self.defaultDuration
        }

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

        installGlobalShortcutHandler()
        registerGlobalShortcut()
    }

    deinit {
        if let globalHotKey {
            UnregisterEventHotKey(globalHotKey)
        }

        if let globalHotKeyHandler {
            RemoveEventHandler(globalHotKeyHandler)
        }
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
        guard !isLocked, isAccessibilityEnabled else { return }
        
        let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return nil }

            let locker = Unmanaged<KeyboardLocker>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            let activeModifiers = event.flags
                .intersection(KeyboardLocker.supportedModifierFlags)
            let eventKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isUnlockShortcut =
                type == .keyDown &&
                eventKeyCode == locker.unlockKeyCode &&
                activeModifiers == locker.unlockModifier

            if type == .keyUp, eventKeyCode == locker.unlockKeyCode {
                locker.ignoreUnlockShortcutUntilKeyUp = false
            } else if isUnlockShortcut, !locker.ignoreUnlockShortcutUntilKeyUp {
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
            ignoreUnlockShortcutUntilKeyUp = false
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

        registerGlobalShortcut()
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

    private func installGlobalShortcutHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }

            let locker = Unmanaged<KeyboardLocker>
                .fromOpaque(userData)
                .takeUnretainedValue()

            DispatchQueue.main.async {
                locker.lockFromGlobalShortcut()
            }

            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &globalHotKeyHandler
        )

        if status != noErr {
            globalShortcutError = "Global shortcut could not be enabled."
        }
    }

    private func registerGlobalShortcut() {
        if let globalHotKey {
            UnregisterEventHotKey(globalHotKey)
            self.globalHotKey = nil
        }

        guard globalHotKeyHandler != nil else { return }

        let hotKeyID = Self.lockHotKeyID
        let status = RegisterEventHotKey(
            UInt32(unlockKeyCode),
            carbonModifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &globalHotKey
        )

        globalShortcutError = status == noErr
            ? nil
            : "This shortcut is already in use."
    }

    private var carbonModifierFlags: UInt32 {
        switch unlockModifier {
        case .maskCommand:
            return UInt32(cmdKey)
        case .maskAlternate:
            return UInt32(optionKey)
        case .maskShift:
            return UInt32(shiftKey)
        default:
            return UInt32(controlKey)
        }
    }

    private func lockFromGlobalShortcut() {
        guard !isLocked else { return }

        ignoreUnlockShortcutUntilKeyUp = true
        startLocking()

        if !isLocked {
            ignoreUnlockShortcutUntilKeyUp = false
        }
    }
}
