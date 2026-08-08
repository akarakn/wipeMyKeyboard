import Foundation
import Cocoa
import CoreGraphics
import Combine
import Carbon
import LocalAuthentication

struct HideableApplication: Identifiable {
    let bundleIdentifier: String
    let displayName: String
    let icon: NSImage?
    let isRunning: Bool

    var id: String {
        bundleIdentifier
    }
}

class KeyboardLocker: ObservableObject {
    static let infiniteDurationValue = 130.0

    @Published var isLocked: Bool = false
    @Published var timeRemaining: Int = 0
    @Published private(set) var hideableApplications: [HideableApplication] = []
    @Published private(set) var selectedApplicationBundleIdentifiers: Set<String>
    @Published var duration: Double {
        didSet {
            UserDefaults.standard.set(duration, forKey: DefaultsKey.duration)
        }
    }
    @Published var lockKeyboard: Bool {
        didSet {
            UserDefaults.standard.set(lockKeyboard, forKey: DefaultsKey.lockKeyboard)
        }
    }
    @Published var lockPointingDevices: Bool {
        didSet {
            UserDefaults.standard.set(
                lockPointingDevices,
                forKey: DefaultsKey.lockPointingDevices
            )
        }
    }

    @Published private(set) var unlockKeyCode: Int64
    @Published private(set) var unlockModifier: CGEventFlags
    @Published private(set) var unlockKeyName: String
    @Published private(set) var globalShortcutError: String?
    @Published private(set) var authenticationInProgress = false
    @Published private(set) var authenticationError: String?

    private static let defaultUnlockKeyCode: Int64 = 53
    private static let defaultUnlockModifier: CGEventFlags = .maskControl
    private static let defaultUnlockKeyName = "Esc"
    private static let defaultDuration = 30.0
    private static let minimumDuration = 10.0
    private static let defaultLockKeyboard = true
    private static let defaultLockPointingDevices = true
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
    private static let authenticationRestrictedModifierFlags: CGEventFlags = [
        .maskCommand,
        .maskControl
    ]

    private enum DefaultsKey {
        static let duration = "duration"
        static let lockKeyboard = "lockKeyboard"
        static let lockPointingDevices = "lockPointingDevices"
        static let unlockKeyCode = "unlockKeyCode"
        static let unlockModifier = "unlockModifier"
        static let unlockKeyName = "unlockKeyName"
        static let selectedApplicationBundleIdentifiers =
            "selectedApplicationBundleIdentifiers"
        static let selectedApplicationDisplayNames =
            "selectedApplicationDisplayNames"
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: AnyCancellable?
    private var globalHotKey: EventHotKeyRef?
    private var globalHotKeyHandler: EventHandlerRef?
    private var authenticationContext: LAContext?
    private var ignoreUnlockShortcutUntilKeyUp = false
    private var selectedApplicationDisplayNames: [String: String]
    private var applicationsHiddenForCurrentLock: Set<pid_t> = []
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        let defaults = UserDefaults.standard
        let savedApplicationBundleIdentifiers = defaults.stringArray(
            forKey: DefaultsKey.selectedApplicationBundleIdentifiers
        ) ?? []
        let savedApplicationDisplayNames = defaults.dictionary(
            forKey: DefaultsKey.selectedApplicationDisplayNames
        )?.compactMapValues { $0 as? String } ?? [:]

        if defaults.object(forKey: DefaultsKey.duration) == nil {
            self.duration = Self.defaultDuration
        } else {
            let savedDuration = defaults.double(forKey: DefaultsKey.duration)
            self.duration = (Self.minimumDuration...Self.infiniteDurationValue)
                .contains(savedDuration)
                ? savedDuration
                : Self.defaultDuration
        }

        self.lockKeyboard = defaults.object(forKey: DefaultsKey.lockKeyboard) == nil
            ? Self.defaultLockKeyboard
            : defaults.bool(forKey: DefaultsKey.lockKeyboard)

        self.lockPointingDevices =
            defaults.object(forKey: DefaultsKey.lockPointingDevices) == nil
            ? Self.defaultLockPointingDevices
            : defaults.bool(forKey: DefaultsKey.lockPointingDevices)

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

        self.selectedApplicationBundleIdentifiers = Set(
            savedApplicationBundleIdentifiers
        )
        self.selectedApplicationDisplayNames = savedApplicationDisplayNames

        refreshHideableApplications()
        installWorkspaceObservers()
        installGlobalShortcutHandler()
        registerGlobalShortcut()
        installCLIControl()
    }

    deinit {
        authenticationContext?.invalidate()

        if let globalHotKey {
            UnregisterEventHotKey(globalHotKey)
        }

        if let globalHotKeyHandler {
            RemoveEventHandler(globalHotKeyHandler)
        }

        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceNotificationCenter.removeObserver(observer)
        }

        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CLIControlProtocol.notificationName,
            nil
        )
    }

    var isInfiniteDuration: Bool {
        duration >= Self.infiniteDurationValue
    }

    var hasLockTargets: Bool {
        lockKeyboard || lockPointingDevices
    }

    var selectedApplicationCount: Int {
        selectedApplicationBundleIdentifiers.count
    }

    var lockedDevicesDescription: String {
        switch (lockKeyboard, lockPointingDevices) {
        case (true, true):
            return "Keyboard, Mouse & Trackpad"
        case (true, false):
            return "Keyboard"
        case (false, true):
            return "Mouse & Trackpad"
        case (false, false):
            return "None"
        }
    }

    func isApplicationSelected(_ application: HideableApplication) -> Bool {
        selectedApplicationBundleIdentifiers.contains(
            application.bundleIdentifier
        )
    }

    func setApplication(
        _ application: HideableApplication,
        selected: Bool
    ) {
        var updatedBundleIdentifiers = selectedApplicationBundleIdentifiers

        if selected {
            updatedBundleIdentifiers.insert(application.bundleIdentifier)
            selectedApplicationDisplayNames[application.bundleIdentifier] =
                application.displayName
        } else {
            updatedBundleIdentifiers.remove(application.bundleIdentifier)
            selectedApplicationDisplayNames.removeValue(
                forKey: application.bundleIdentifier
            )
        }

        selectedApplicationBundleIdentifiers = updatedBundleIdentifiers
        persistSelectedApplications()
        refreshHideableApplications()
    }

    func refreshHideableApplications() {
        let currentBundleIdentifier = Bundle.main.bundleIdentifier
        let runningApplications = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular &&
                !$0.isTerminated &&
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
                $0.bundleIdentifier != currentBundleIdentifier
        }

        var applicationsByBundleIdentifier: [String: HideableApplication] = [:]

        for runningApplication in runningApplications {
            guard let bundleIdentifier = runningApplication.bundleIdentifier else {
                continue
            }

            let displayName = runningApplication.localizedName
                ?? selectedApplicationDisplayNames[bundleIdentifier]
                ?? bundleIdentifier

            applicationsByBundleIdentifier[bundleIdentifier] =
                HideableApplication(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName,
                    icon: runningApplication.icon,
                    isRunning: true
                )

            if selectedApplicationBundleIdentifiers.contains(bundleIdentifier) {
                selectedApplicationDisplayNames[bundleIdentifier] = displayName
            }
        }

        for bundleIdentifier in selectedApplicationBundleIdentifiers
        where applicationsByBundleIdentifier[bundleIdentifier] == nil {
            let displayName = selectedApplicationDisplayNames[bundleIdentifier]
                ?? bundleIdentifier
            let icon = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ).map {
                NSWorkspace.shared.icon(forFile: $0.path)
            }

            applicationsByBundleIdentifier[bundleIdentifier] =
                HideableApplication(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName,
                    icon: icon,
                    isRunning: false
                )
        }

        hideableApplications = applicationsByBundleIdentifier.values.sorted {
            if $0.isRunning != $1.isRunning {
                return $0.isRunning
            }

            return $0.displayName.localizedCaseInsensitiveCompare(
                $1.displayName
            ) == .orderedAscending
        }

        persistSelectedApplications()
    }
    
    var isAccessibilityEnabled: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func startLocking() {
        guard !isLocked, hasLockTargets, isAccessibilityEnabled else { return }
        
        let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return nil }

            let locker = Unmanaged<KeyboardLocker>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let eventTap = locker.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            let isKeyboardEvent =
                type == .keyDown ||
                type == .keyUp ||
                type == .flagsChanged ||
                type.rawValue == 14

            if isKeyboardEvent {
                let activeModifiers = event.flags
                    .intersection(KeyboardLocker.supportedModifierFlags)
                let eventKeyCode = event.getIntegerValueField(
                    .keyboardEventKeycode
                )
                let isUnlockShortcut =
                    type == .keyDown &&
                    eventKeyCode == locker.unlockKeyCode &&
                    activeModifiers == locker.unlockModifier

                if type == .keyUp,
                   eventKeyCode == locker.unlockKeyCode,
                   locker.ignoreUnlockShortcutUntilKeyUp {
                    locker.ignoreUnlockShortcutUntilKeyUp = false
                    return nil
                }

                if isUnlockShortcut,
                   !locker.ignoreUnlockShortcutUntilKeyUp {
                    DispatchQueue.main.async {
                        locker.requestAuthenticatedUnlock()
                    }
                    return nil
                }

                let isPasswordEntryEvent =
                    type == .keyDown ||
                    type == .keyUp ||
                    type == .flagsChanged
                let hasRestrictedAuthenticationModifier = !activeModifiers
                    .intersection(
                        KeyboardLocker.authenticationRestrictedModifierFlags
                    )
                    .isEmpty

                if locker.authenticationInProgress,
                   isPasswordEntryEvent,
                   !hasRestrictedAuthenticationModifier {
                    return Unmanaged.passUnretained(event)
                }

                return locker.lockKeyboard
                    ? nil
                    : Unmanaged.passUnretained(event)
            }

            return locker.lockPointingDevices
                ? nil
                : Unmanaged.passUnretained(event)
        }
        
        let keyboardEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << 14) // NX_SYSDEFINED for media/function keys

        let pointingDeviceEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.tabletPointer.rawValue) |
            (1 << CGEventType.tabletProximity.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)

        let eventMask = keyboardEventMask |
            (lockPointingDevices ? pointingDeviceEventMask : 0)
        
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
        hideSelectedApplications()

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

    func requestAuthenticatedUnlock() {
        guard isLocked, !authenticationInProgress else { return }

        let context = LAContext()
        context.localizedCancelTitle = "Keep Locked"
        context.localizedFallbackTitle = "Use Password"
        context.touchIDAuthenticationAllowableReuseDuration = 0

        var policyError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &policyError
        ) else {
            authenticationError = policyError?.localizedDescription
                ?? "Touch ID or password authentication is unavailable."
            return
        }

        authenticationContext?.invalidate()
        authenticationContext = context
        authenticationInProgress = true
        authenticationError = nil

        NSApplication.shared.activate(ignoringOtherApps: true)

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "unlock keyboard and pointing devices"
        ) { [weak self, weak context] success, error in
            DispatchQueue.main.async {
                guard
                    let self,
                    let context,
                    self.authenticationContext === context
                else {
                    return
                }

                self.authenticationContext = nil
                self.authenticationInProgress = false

                if success {
                    self.stopLocking()
                } else if (error as? LAError)?.code != .userCancel {
                    self.authenticationError = error?.localizedDescription
                        ?? "Authentication failed."
                }
            }
        }
    }

    private func stopLocking(playCompletionSound: Bool = false) {
        authenticationContext?.invalidate()
        authenticationContext = nil
        authenticationInProgress = false
        authenticationError = nil

        if let tap = self.eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = self.runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }

        restoreApplicationsHiddenForCurrentLock()
        self.timer?.cancel()
        self.timer = nil
        self.isLocked = false
        self.timeRemaining = 0
        
        if playCompletionSound {
            NSSound(named: "Glass")?.play()
        }
    }

    private func persistSelectedApplications() {
        let defaults = UserDefaults.standard
        defaults.set(
            selectedApplicationBundleIdentifiers.sorted(),
            forKey: DefaultsKey.selectedApplicationBundleIdentifiers
        )
        defaults.set(
            selectedApplicationDisplayNames,
            forKey: DefaultsKey.selectedApplicationDisplayNames
        )
    }

    private func installWorkspaceObservers() {
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
        let notificationNames: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]

        for notificationName in notificationNames {
            let observer = workspaceNotificationCenter.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }

                self.refreshHideableApplications()

                if self.isLocked {
                    self.hideSelectedApplications()
                }
            }

            workspaceObservers.append(observer)
        }
    }

    private func hideSelectedApplications() {
        for application in NSWorkspace.shared.runningApplications {
            guard
                application.activationPolicy == .regular,
                !application.isTerminated,
                !application.isHidden,
                application.processIdentifier !=
                    ProcessInfo.processInfo.processIdentifier,
                let bundleIdentifier = application.bundleIdentifier,
                selectedApplicationBundleIdentifiers.contains(bundleIdentifier)
            else {
                continue
            }

            if application.hide() {
                applicationsHiddenForCurrentLock.insert(
                    application.processIdentifier
                )
            }
        }
    }

    private func restoreApplicationsHiddenForCurrentLock() {
        for processIdentifier in applicationsHiddenForCurrentLock {
            guard
                let application = NSRunningApplication(
                    processIdentifier: processIdentifier
                ),
                !application.isTerminated
            else {
                continue
            }

            application.unhide()
        }

        applicationsHiddenForCurrentLock.removeAll()
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

    private func installCLIControl() {
        try? CLIControlProtocol.prepareControlDirectory()

        let callback: CFNotificationCallback = {
            _, observer, _, _, _ in
            guard let observer else { return }

            let locker = Unmanaged<KeyboardLocker>
                .fromOpaque(observer)
                .takeUnretainedValue()

            DispatchQueue.main.async {
                locker.processPendingCLIRequests()
            }
        }

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            callback,
            CLIControlProtocol.notificationName.rawValue,
            nil,
            .deliverImmediately
        )

        DispatchQueue.main.async {
            self.processPendingCLIRequests()
        }
    }

    private func processPendingCLIRequests() {
        guard
            let requestURLs = try? CLIControlProtocol.pendingRequestURLs()
        else {
            return
        }

        for requestURL in requestURLs {
            defer {
                try? FileManager.default.removeItem(at: requestURL)
            }

            guard
                let requestData = try? Data(contentsOf: requestURL),
                let request = try? JSONDecoder()
                    .decode(CLIControlRequest.self, from: requestData)
            else {
                continue
            }

            let response = response(for: request)
            guard
                let responseData = try? JSONEncoder().encode(response)
            else {
                continue
            }

            try? responseData.write(
                to: CLIControlProtocol.responseURL(for: request.id),
                options: .atomic
            )
        }
    }

    private func response(
        for request: CLIControlRequest
    ) -> CLIControlResponse {
        let result: (success: Bool, message: String)

        switch request.command {
        case .lock:
            if isLocked {
                result = (true, "Input is already locked.")
            } else if !hasLockTargets {
                result = (false, "No input devices are selected.")
            } else {
                startLocking()
                result = isLocked
                    ? (true, "Locked: \(lockedDevicesDescription).")
                    : (false, "Unable to lock input. Check Accessibility permission.")
            }

        case .unlock:
            if isLocked {
                stopLocking()
                result = (true, "Input unlocked.")
            } else {
                result = (true, "Input is already unlocked.")
            }

        case .status:
            result = isLocked
                ? (true, "Locked: \(lockedDevicesDescription).")
                : (true, "Unlocked.")
        }

        return CLIControlResponse(
            id: request.id,
            success: result.success,
            message: result.message,
            isLocked: isLocked
        )
    }
}
