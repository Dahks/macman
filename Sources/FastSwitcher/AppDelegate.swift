import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var eventTap: CFMachPort?
    var switcher: SwitcherPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !requestAccessibility() {
            print("ERROR: Accessibility permission required.")
            print("Go to System Settings > Privacy & Security > Accessibility")
            print("and add FastSwitcher to the list.")
            print("Restart after granting permission.")
        }

        switcher = SwitcherPanel()
        installEventTap()

        print("FastSwitcher running. Press Cmd+Tab to switch windows.")
        print("Press Ctrl+C to quit.")
    }

    func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func installEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let userInfo = userInfo {
                        let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
                        if let tap = appDelegate.eventTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                        }
                    }
                    return Unmanaged.passRetained(event)
                }

                guard let userInfo = userInfo else {
                    return Unmanaged.passRetained(event)
                }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
                return appDelegate.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            print("ERROR: Failed to create event tap. Is accessibility permission granted?")
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    var isSwitcherActive = false

    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        // Key between left-Shift and Z on ISO keyboards (< > key), keycode 50
        let kAngleBracketKeyCode: Int64 = 50

        // Number keycodes: 1-9 on main keyboard
        // 1=18, 2=19, 3=20, 4=21, 5=23, 6=22, 7=26, 8=28, 9=25
        let numberKeyCodes: [Int64: Int] = [
            18: 0, 19: 1, 20: 2, 21: 3, 23: 4,
            22: 5, 26: 6, 28: 7, 25: 8
        ]

        // Cmd+Ctrl+1-9 — jump directly to app by launch order
        if type == .keyDown
            && flags.contains(.maskCommand)
            && flags.contains(.maskControl),
           let appIndex = numberKeyCodes[keyCode] {
            switcher?.activateAppAtIndex(appIndex)
            return nil
        }

        // Cmd+< pressed (Cmd+Shift+< = >  = reverse)
        if type == .keyDown && keyCode == kAngleBracketKeyCode && flags.contains(.maskCommand) {
            let reverse = flags.contains(.maskShift)

            if !isSwitcherActive {
                isSwitcherActive = true
                switcher?.show(reverse: reverse)
            } else {
                switcher?.cycleSelection(reverse: reverse)
            }
            return nil
        }

        // Cmd released — commit
        if type == .flagsChanged && isSwitcherActive && !flags.contains(.maskCommand) {
            isSwitcherActive = false
            switcher?.commitAndHide()
            return nil
        }

        // Escape — cancel
        if type == .keyDown && keyCode == 53 && isSwitcherActive {
            isSwitcherActive = false
            switcher?.hide()
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}
