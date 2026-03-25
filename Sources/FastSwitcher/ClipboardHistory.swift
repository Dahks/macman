import Cocoa

class ClipboardHistory {
    static let shared = ClipboardHistory()

    private(set) var entries: [String] = []
    private var lastChangeCount: Int
    private let maxEntries = 50

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
        // Seed with current clipboard content
        if let current = NSPasteboard.general.string(forType: .string), !current.isEmpty {
            entries.append(current)
        }
        startPolling()
    }

    private func startPolling() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    private func checkForChanges() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let text = pb.string(forType: .string), !text.isEmpty else { return }

        // Remove duplicate if it already exists, then insert at front
        entries.removeAll { $0 == text }
        entries.insert(text, at: 0)

        // Cap size
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }

    func copyToClipboard(at index: Int) {
        guard index >= 0 && index < entries.count else { return }
        let text = entries[index]
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount  // don't re-detect our own write

        // Move to front
        entries.removeAll { $0 == text }
        entries.insert(text, at: 0)
    }
}

// MARK: - ClipboardPanel

class ClipboardPanel {
    let panel: KeyablePanel
    let listView: ClipboardListView
    var selectedIndex: Int = 0
    var isVisible: Bool = false

    init() {
        let frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        panel = KeyablePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let vibrancy = NSVisualEffectView(frame: frame)
        vibrancy.material = .menu
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 10
        vibrancy.layer?.masksToBounds = true

        listView = ClipboardListView(frame: frame)
        listView.autoresizingMask = [.width, .height]
        vibrancy.addSubview(listView)
        panel.contentView = vibrancy
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let entries = ClipboardHistory.shared.entries
        guard !entries.isEmpty else { return }

        selectedIndex = 0
        listView.update(entries: entries, selectedIndex: selectedIndex)
        positionPanel()
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel.orderOut(nil)
        isVisible = false
    }

    func moveSelection(down: Bool) {
        let count = ClipboardHistory.shared.entries.count
        guard count > 0 else { return }
        if down {
            selectedIndex = (selectedIndex + 1) % count
        } else {
            selectedIndex = (selectedIndex - 1 + count) % count
        }
        listView.update(entries: ClipboardHistory.shared.entries, selectedIndex: selectedIndex)
    }

    func confirmSelection() {
        ClipboardHistory.shared.copyToClipboard(at: selectedIndex)
        hide()
    }

    private func positionPanel() {
        let entries = ClipboardHistory.shared.entries
        let rowHeight: CGFloat = 24
        let maxVisible = min(entries.count, 12)
        let height = CGFloat(maxVisible) * rowHeight + 16
        let width: CGFloat = 400

        let screen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]
        let screenFrame = screen.frame
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - height) / 2

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        if let vibrancy = panel.contentView as? NSVisualEffectView {
            let mask = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
                NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            vibrancy.maskImage = mask
        }
    }
}

// MARK: - ClipboardListView

class ClipboardListView: NSView {
    private var entries: [String] = []
    private var selectedIndex: Int = 0

    private let rowHeight: CGFloat = 24
    private let padding: CGFloat = 8
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let maxVisible = 12

    func update(entries: [String], selectedIndex: Int) {
        self.entries = entries
        self.selectedIndex = selectedIndex
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let visibleCount = min(entries.count, maxVisible)

        // Scroll so selected item is visible
        let scrollOffset: Int
        if selectedIndex < maxVisible {
            scrollOffset = 0
        } else {
            scrollOffset = selectedIndex - maxVisible + 1
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.8),
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]

        for i in 0..<visibleCount {
            let entryIndex = i + scrollOffset
            guard entryIndex < entries.count else { break }

            let y = bounds.height - CGFloat(i + 1) * rowHeight - padding / 2

            // Selection highlight
            if entryIndex == selectedIndex {
                let selRect = NSRect(x: padding, y: y, width: bounds.width - padding * 2, height: rowHeight)
                let selPath = NSBezierPath(roundedRect: selRect, xRadius: 4, yRadius: 4)
                NSColor(white: 1.0, alpha: 0.12).setFill()
                selPath.fill()
            }

            // Truncate and clean up the entry text
            var text = entries[entryIndex]
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
            if text.count > 60 {
                text = String(text.prefix(57)) + "..."
            }

            let drawAttrs = entryIndex == selectedIndex ? selectedAttrs : attrs
            let textY = y + (rowHeight - font.pointSize) / 2
            (text as NSString).draw(
                at: NSPoint(x: padding + 6, y: textY),
                withAttributes: drawAttrs
            )
        }
    }
}
