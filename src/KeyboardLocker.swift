import Foundation
import Cocoa
import CoreGraphics
import Combine

class KeyboardLocker: ObservableObject {
    @Published var isLocked: Bool = false
    @Published var timeRemaining: Int = 0
    @Published var duration: Double = 30.0
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: AnyCancellable?
    
    var isAccessibilityEnabled: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func startLocking() {
        guard isAccessibilityEnabled else { return }
        
        let eventCallback: CGEventTapCallBack = { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
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
            userInfo: nil
        ) else {
            print("Failed to create event tap")
            return
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), self.runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        self.isLocked = true
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
}
