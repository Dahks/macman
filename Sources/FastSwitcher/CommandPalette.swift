import Cocoa

class CommandPalette: NSObject, NSTextFieldDelegate {
    let cmdPanel: KeyablePanel
    let inputField: NSTextField
    let hintLabel: NSTextField
    var isVisible: Bool = false

    /// Called with the command string when user presses Enter
    var onExecute: ((String) -> String?)?

    override init() {
        let width: CGFloat = 350
        let height: CGFloat = 60
        let frame = NSRect(x: 0, y: 0, width: width, height: height)

        cmdPanel = KeyablePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        cmdPanel.level = .screenSaver
        cmdPanel.isOpaque = false
        cmdPanel.backgroundColor = .clear
        cmdPanel.hasShadow = true
        cmdPanel.animationBehavior = .none
        cmdPanel.hidesOnDeactivate = false
        cmdPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let vibrancy = NSVisualEffectView(frame: frame)
        vibrancy.material = .menu
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 10
        vibrancy.layer?.masksToBounds = true

        let mask = NSImage(size: frame.size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        vibrancy.maskImage = mask

        // Input field
        inputField = NSTextField(frame: NSRect(x: 10, y: height - 30, width: width - 20, height: 22))
        inputField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        inputField.placeholderString = "swap 7 0, move 3 1, help"
        inputField.isBordered = false
        inputField.drawsBackground = true
        inputField.backgroundColor = NSColor(white: 0.15, alpha: 0.9)
        inputField.textColor = .white
        inputField.focusRingType = .none
        inputField.wantsLayer = true
        inputField.layer?.cornerRadius = 4
        vibrancy.addSubview(inputField)

        // Hint / feedback label
        hintLabel = NSTextField(frame: NSRect(x: 12, y: 4, width: width - 24, height: 18))
        hintLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        hintLabel.stringValue = "swap <a> <b> | move <from> <to>"
        hintLabel.isBordered = false
        hintLabel.isEditable = false
        hintLabel.drawsBackground = false
        vibrancy.addSubview(hintLabel)

        cmdPanel.contentView = vibrancy

        super.init()
        inputField.delegate = self
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        inputField.stringValue = ""
        hintLabel.stringValue = "swap <a> <b> | move <from> <to>"
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        positionPanel()
        cmdPanel.orderFrontRegardless()
        cmdPanel.makeKey()
        cmdPanel.makeFirstResponder(inputField)
        isVisible = true
    }

    func hide() {
        cmdPanel.orderOut(nil)
        isVisible = false
    }

    private func positionPanel() {
        let width: CGFloat = 350
        let height: CGFloat = 60
        let screen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]
        let screenFrame = screen.frame
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - height) / 2
        cmdPanel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let cmd = inputField.stringValue.trimmingCharacters(in: .whitespaces)
            if !cmd.isEmpty {
                if let error = onExecute?(cmd) {
                    hintLabel.stringValue = error
                    hintLabel.textColor = NSColor(red: 1, green: 0.5, blue: 0.5, alpha: 0.9)
                } else {
                    hide()
                }
            }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hide()
            return true
        }
        return false
    }
}
