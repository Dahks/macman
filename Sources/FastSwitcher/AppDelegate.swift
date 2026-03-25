import Cocoa
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    var eventTap: CFMachPort?
    var switcher: SwitcherPanel?
    var clipboardPanel: ClipboardPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !requestAccessibility() {
            print("ERROR: Accessibility permission required.")
            print("Go to System Settings > Privacy & Security > Accessibility")
            print("and add FastSwitcher to the list.")
            print("Restart after granting permission.")
        }

        switcher = SwitcherPanel()
        clipboardPanel = ClipboardPanel()
        _ = ClipboardHistory.shared  // start polling
        installEventTap()

        isSwitcherActive = true
        isOverviewMode = true
        switcher?.showOverview()

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
    var isOverviewMode = false  // true = toggle mode (stays open), false = hold mode (commits on Cmd release)

    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // fn+h/j/k/l → arrow keys — must run FIRST so all modes see arrow keycodes
        // h=4→left(123), j=38→down(125), k=40→up(126), l=37→right(124)
        if (type == .keyDown || type == .keyUp) && flags.contains(.maskSecondaryFn) {
            let arrowMap: [Int64: Int64] = [4: 123, 38: 125, 40: 126, 37: 124]
            if let arrowCode = arrowMap[keyCode] {
                let isDown = type == .keyDown
                if let newEvent = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(arrowCode), keyDown: isDown) {
                    var newFlags = flags
                    newFlags.remove(.maskSecondaryFn)
                    newEvent.flags = newFlags
                    // Re-enter handleEvent with the remapped event
                    return handleEvent(proxy: proxy, type: type, event: newEvent)
                }
            }
        }

        // Clipboard panel mode — forward key events to search field
        if clipboardPanel?.isVisible == true {
            if type == .keyDown || type == .keyUp {
                if let nsEvent = NSEvent(cgEvent: event) {
                    NSApp.postEvent(nsEvent, atStart: true)
                }
                return nil
            }
            return Unmanaged.passRetained(event)
        }

        // Ctrl+Shift+Space (keyCode 49) — toggle clipboard history
        if type == .keyDown && keyCode == 49
            && flags.contains(.maskControl) && flags.contains(.maskShift) && !flags.contains(.maskCommand) {
            clipboardPanel?.toggle()
            return nil
        }

        // Rename mode — intercept events and forward to our own app's text field
        if switcher?.isRenaming == true {
            if type == .keyDown && keyCode == 53 {
                // Escape cancels rename
                switcher?.tmuxView.cancelRename()
                return nil
            }
            // Re-post key events to our own application so the NSTextField receives them
            if type == .keyDown || type == .keyUp {
                if let nsEvent = NSEvent(cgEvent: event) {
                    NSApp.postEvent(nsEvent, atStart: true)
                }
                return nil  // consume the original event
            }
            return Unmanaged.passRetained(event)
        }

        // Key between left-Shift and Z on ISO keyboards (< > key), keycode 50
        let kAngleBracketKeyCode: Int64 = 50

        // Number keycodes: 1-9 on main keyboard
        // 1=18, 2=19, 3=20, 4=21, 5=23, 6=22, 7=26, 8=28, 9=25
        // 0=29, 1=18, 2=19, 3=20, 4=21, 5=23, 6=22, 7=26, 8=28, 9=25
        let numberKeyCodes: [Int64: Int] = [
            29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5,
            22: 6, 26: 7, 28: 8, 25: 9
        ]

        // § / ° key (above Tab on ISO keyboards), keycode 10
        let kSectionKeyCode: Int64 = 10

        // Ctrl+S (keyCode 1) — cycle view mode
        if type == .keyDown && keyCode == 1
            && flags.contains(.maskControl) && !flags.contains(.maskCommand) {
            switcher?.cycleViewMode()
            return nil
        }

        // Ctrl+, (keyCode 43) — rename current window (tmux mode only)
        if type == .keyDown && keyCode == 43
            && flags.contains(.maskControl) && !flags.contains(.maskCommand) {
            print("Ctrl+, pressed, viewMode=\(String(describing: switcher?.viewMode))")
            if switcher?.viewMode == .tmux {
                switcher?.beginRenameMode()
            }
            return nil
        }

        // Ctrl+° — toggle app overview
        if type == .keyDown && keyCode == kSectionKeyCode
            && flags.contains(.maskControl) && !flags.contains(.maskCommand) {
            if isSwitcherActive && isOverviewMode {
                isSwitcherActive = false
                isOverviewMode = false
                switcher?.hide()
            } else {
                isSwitcherActive = true
                isOverviewMode = true
                switcher?.showOverview()
            }
            return nil
        }

        // Ctrl+1-9 — jump directly to app/window by index
        if type == .keyDown
            && flags.contains(.maskControl)
            && !flags.contains(.maskCommand),
           let index = numberKeyCodes[keyCode] {
            if switcher?.viewMode == .tmux {
                switcher?.activateWindowAtIndex(index)
            } else {
                switcher?.activateAppAtIndex(index)
            }
            return nil
        }

        // Cmd+< or Cmd+Tab pressed
        let kTabKeyCode: Int64 = 48
        if type == .keyDown && (keyCode == kAngleBracketKeyCode || keyCode == kTabKeyCode) && flags.contains(.maskCommand) {
            let reverse = flags.contains(.maskShift)

            if isOverviewMode {
                // Hide overview, switch to MRU mode (keep wasOverviewOpen flag)
                isOverviewMode = false
                switcher?.panel.orderOut(nil)
                isSwitcherActive = true
                switcher?.show(reverse: reverse)
            } else if !isSwitcherActive {
                isSwitcherActive = true
                switcher?.show(reverse: reverse)
            } else {
                switcher?.cycleSelection(reverse: reverse)
            }
            return nil
        }

        // Cmd released — commit
        if type == .flagsChanged && isSwitcherActive && !isOverviewMode && !flags.contains(.maskCommand) {
            let shouldRestoreOverview = switcher?.wasOverviewOpen ?? false
            isSwitcherActive = false
            switcher?.commitAndHide()

            // Restore overview if it was open before
            if shouldRestoreOverview {
                isSwitcherActive = true
                isOverviewMode = true
                switcher?.showOverview()
            }
            return nil
        }

        // Escape — cancel MRU hold-mode only, not persistent overview
        if type == .keyDown && keyCode == 53 && isSwitcherActive && !isOverviewMode {
            isSwitcherActive = false
            switcher?.commitAndHide()

            // Restore overview if it was open before
            let shouldRestoreOverview = switcher?.wasOverviewOpen ?? false
            if shouldRestoreOverview {
                isSwitcherActive = true
                isOverviewMode = true
                switcher?.showOverview()
            }
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}
