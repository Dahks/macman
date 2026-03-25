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

    /// Filter entries by regex pattern. Returns all entries if pattern is empty or invalid.
    func filter(pattern: String) -> [String] {
        guard !pattern.isEmpty else { return entries }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return entries
        }
        return entries.filter { entry in
            let range = NSRange(entry.startIndex..., in: entry)
            return regex.firstMatch(in: entry, range: range) != nil
        }
    }

    func copyToClipboard(entry: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry, forType: .string)
        lastChangeCount = pb.changeCount

        // Move to front
        entries.removeAll { $0 == entry }
        entries.insert(entry, at: 0)
    }
}

// MARK: - ClipboardPanel

class ClipboardPanel: NSObject, NSTextFieldDelegate {
    let panel: KeyablePanel
    let listView: ClipboardListView
    let searchField: NSTextField
    var selectedIndex: Int = 0
    var isVisible: Bool = false
    var filteredEntries: [String] = []

    override init() {
        let frame = NSRect(x: 0, y: 0, width: 450, height: 340)
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

        // Search field at the top
        searchField = NSTextField(frame: NSRect(x: 10, y: frame.height - 30, width: frame.width - 20, height: 22))
        searchField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        searchField.placeholderString = "Search (regex)..."
        searchField.isBordered = false
        searchField.drawsBackground = true
        searchField.backgroundColor = NSColor(white: 0.15, alpha: 0.9)
        searchField.textColor = .white
        searchField.focusRingType = .none
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 4
        vibrancy.addSubview(searchField)

        // List view below the search field
        let listFrame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height - 36)
        listView = ClipboardListView(frame: listFrame)
        listView.autoresizingMask = [.width]
        vibrancy.addSubview(listView)

        panel.contentView = vibrancy

        super.init()
        searchField.delegate = self
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

        searchField.stringValue = ""
        filteredEntries = entries
        selectedIndex = 0
        listView.update(entries: filteredEntries, selectedIndex: selectedIndex)
        positionPanel()
        panel.orderFrontRegardless()
        isVisible = true

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        panel.orderOut(nil)
        panel.resignKey()
        isVisible = false
    }

    func moveSelection(down: Bool) {
        guard !filteredEntries.isEmpty else { return }
        if down {
            selectedIndex = (selectedIndex + 1) % filteredEntries.count
        } else {
            selectedIndex = (selectedIndex - 1 + filteredEntries.count) % filteredEntries.count
        }
        listView.update(entries: filteredEntries, selectedIndex: selectedIndex)
    }

    func confirmSelection() {
        guard selectedIndex >= 0 && selectedIndex < filteredEntries.count else { return }
        ClipboardHistory.shared.copyToClipboard(entry: filteredEntries[selectedIndex])
        hide()
    }

    private func updateFilter() {
        let pattern = searchField.stringValue
        filteredEntries = ClipboardHistory.shared.filter(pattern: pattern)
        selectedIndex = 0
        listView.update(entries: filteredEntries, selectedIndex: selectedIndex)
        positionPanel()
    }

    private func positionPanel() {
        let width: CGFloat = 450
        let searchHeight: CGFloat = 36
        let listHeight = filteredEntries.isEmpty ? CGFloat(24 + 16) : listView.requiredHeight(width: width)
        let height = listHeight + searchHeight

        let screen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens[0]
        let screenFrame = screen.frame
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + (screenFrame.height - height) / 2

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        // Reposition subviews
        searchField.frame = NSRect(x: 10, y: height - 30, width: width - 20, height: 22)
        listView.frame = NSRect(x: 0, y: 0, width: width, height: height - searchHeight)

        if let vibrancy = panel.contentView as? NSVisualEffectView {
            let mask = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
                NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            vibrancy.maskImage = mask
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        updateFilter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            confirmSelection()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hide()
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            moveSelection(down: true)
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            moveSelection(down: false)
            return true
        }
        return false
    }
}

// MARK: - ClipboardListView

class ClipboardListView: NSView {
    private var entries: [String] = []
    private var selectedIndex: Int = 0

    private let rowHeight: CGFloat = 24
    private let maxExpandedHeight: CGFloat = 120
    private let padding: CGFloat = 8
    let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let maxVisible = 12

    func update(entries: [String], selectedIndex: Int) {
        self.entries = entries
        self.selectedIndex = selectedIndex
        needsDisplay = true
    }

    /// Compute expanded height for selected entry
    private func expandedHeight(for text: String, width: CGFloat) -> CGFloat {
        let constrainRect = NSRect(x: 0, y: 0, width: width - padding * 2 - 12, height: .greatestFiniteMagnitude)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let boundingRect = (text as NSString).boundingRect(with: constrainRect.size,
                                                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                            attributes: attrs)
        let h = ceil(boundingRect.height) + 8
        return min(max(h, rowHeight), maxExpandedHeight)
    }

    /// Total height needed for visible rows (accounting for expanded selected row)
    func requiredHeight(width: CGFloat) -> CGFloat {
        let visibleCount = min(entries.count, maxVisible)
        let scrollOffset = selectedIndex < maxVisible ? 0 : selectedIndex - maxVisible + 1

        var total: CGFloat = padding
        for i in 0..<visibleCount {
            let entryIndex = i + scrollOffset
            guard entryIndex < entries.count else { break }
            if entryIndex == selectedIndex {
                let text = entries[entryIndex].replacingOccurrences(of: "\t", with: " ")
                total += expandedHeight(for: text, width: width)
            } else {
                total += rowHeight
            }
        }
        return total
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let visibleCount = min(entries.count, maxVisible)
        let scrollOffset = selectedIndex < maxVisible ? 0 : selectedIndex - maxVisible + 1

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.8),
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]

        var y = bounds.height - padding / 2

        for i in 0..<visibleCount {
            let entryIndex = i + scrollOffset
            guard entryIndex < entries.count else { break }

            let isSelected = entryIndex == selectedIndex
            let rawText = entries[entryIndex].replacingOccurrences(of: "\t", with: " ")

            let thisRowHeight: CGFloat
            let displayText: String

            if isSelected {
                thisRowHeight = expandedHeight(for: rawText, width: bounds.width)
                displayText = rawText  // show full text, wrapped
            } else {
                thisRowHeight = rowHeight
                // Single line, truncated
                var line = rawText.replacingOccurrences(of: "\n", with: " ")
                if line.count > 65 {
                    line = String(line.prefix(62)) + "..."
                }
                displayText = line
            }

            y -= thisRowHeight

            // Selection highlight
            if isSelected {
                let selRect = NSRect(x: padding, y: y, width: bounds.width - padding * 2, height: thisRowHeight)
                let selPath = NSBezierPath(roundedRect: selRect, xRadius: 4, yRadius: 4)
                NSColor(white: 1.0, alpha: 0.12).setFill()
                selPath.fill()
            }

            let drawAttrs = isSelected ? selectedAttrs : attrs

            if isSelected {
                // Draw wrapped text in a rect
                let textRect = NSRect(x: padding + 6, y: y + 4,
                                      width: bounds.width - padding * 2 - 12,
                                      height: thisRowHeight - 8)
                (displayText as NSString).draw(in: textRect, withAttributes: drawAttrs)
            } else {
                let textY = y + (thisRowHeight - font.pointSize) / 2
                (displayText as NSString).draw(at: NSPoint(x: padding + 6, y: textY), withAttributes: drawAttrs)
            }
        }
    }
}
