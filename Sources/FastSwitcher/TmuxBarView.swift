import Cocoa

class TmuxBarView: NSView, NSTextFieldDelegate {
    struct Cell {
        let index: Int
        let label: String
        let isActive: Bool    // * marker (frontmost window)
        let isPrevious: Bool  // - marker (previously active)
    }

    var cells: [Cell] = []
    var selectedIndex: Int = -1
    var isRenaming: Bool = false
    private var renameIndex: Int = -1
    private var renameField: NSTextField!

    // Callback when rename is committed
    var onRenameCommit: ((Int, String) -> Void)?
    var onRenameCancel: (() -> Void)?

    private let cellFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private let cellPadding: CGFloat = 12
    private let verticalPadding: CGFloat = 4
    private let horizontalInset: CGFloat = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupRenameField()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupRenameField()
    }

    private func setupRenameField() {
        renameField = NSTextField(frame: .zero)
        renameField.font = cellFont
        renameField.isBordered = false
        renameField.drawsBackground = true
        renameField.backgroundColor = NSColor(white: 0.2, alpha: 0.9)
        renameField.textColor = .white
        renameField.focusRingType = .none
        renameField.isHidden = true
        renameField.delegate = self
        addSubview(renameField)
    }

    func update(cells: [Cell], selectedIndex: Int) {
        self.cells = cells
        self.selectedIndex = selectedIndex
        needsDisplay = true
    }

    /// Returns the total width needed to render all cells.
    func requiredWidth() -> CGFloat {
        var width: CGFloat = horizontalInset * 2
        let attrs: [NSAttributedString.Key: Any] = [.font: cellFont]
        for cell in cells {
            let text = cellText(for: cell)
            let textSize = (text as NSString).size(withAttributes: attrs)
            width += textSize.width + cellPadding
        }
        return max(width, 100)
    }

    private func cellText(for cell: Cell) -> String {
        let suffix = cell.isActive ? "*" : (cell.isPrevious ? "-" : "")
        return "\(cell.index):\(cell.label)\(suffix)"
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: cellFont,
            .foregroundColor: NSColor.white,
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .font: cellFont,
            .foregroundColor: NSColor.white,
        ]

        var x: CGFloat = horizontalInset

        for (i, cell) in cells.enumerated() {
            let text = cellText(for: cell)
            let textSize = (text as NSString).size(withAttributes: attrs)
            let cellWidth = textSize.width + cellPadding

            // Selection highlight
            if i == selectedIndex {
                let selRect = NSRect(
                    x: x,
                    y: verticalPadding,
                    width: cellWidth,
                    height: bounds.height - verticalPadding * 2
                )
                let selPath = NSBezierPath(roundedRect: selRect, xRadius: 4, yRadius: 4)
                NSColor(white: 1.0, alpha: 0.15).setFill()
                selPath.fill()
            }

            // Draw text
            let textY = (bounds.height - textSize.height) / 2
            let drawAttrs = i == selectedIndex ? selectedAttrs : attrs
            // Skip drawing text for the cell being renamed
            if !(isRenaming && i == renameIndex) {
                (text as NSString).draw(
                    at: NSPoint(x: x + cellPadding / 2, y: textY),
                    withAttributes: drawAttrs
                )
            }

            x += cellWidth
        }
    }

    // MARK: - Rename

    func beginRename(at index: Int) {
        guard index >= 0 && index < cells.count else { return }
        isRenaming = true
        renameIndex = index

        // Calculate position of the cell
        let attrs: [NSAttributedString.Key: Any] = [.font: cellFont]
        var x: CGFloat = horizontalInset
        for i in 0..<index {
            let text = cellText(for: cells[i])
            let textSize = (text as NSString).size(withAttributes: attrs)
            x += textSize.width + cellPadding
        }

        let prefix = "\(cells[index].index):"
        let prefixWidth = (prefix as NSString).size(withAttributes: attrs).width
        let currentLabel = cells[index].label
        let labelWidth = max((currentLabel as NSString).size(withAttributes: attrs).width + 20, 60)

        renameField.frame = NSRect(
            x: x + cellPadding / 2 + prefixWidth,
            y: (bounds.height - 20) / 2,
            width: labelWidth,
            height: 20
        )
        renameField.stringValue = currentLabel
        renameField.isHidden = false
        needsDisplay = true

        // Activate our app and make the panel key so the text field can receive input
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        window?.makeFirstResponder(renameField)
        renameField.selectText(nil)
    }

    func commitRename() {
        guard isRenaming else { return }
        let newName = renameField.stringValue
        let index = renameIndex
        isRenaming = false
        renameIndex = -1
        renameField.isHidden = true

        // Revert panel to non-key
        if let panel = window as? NSPanel {
            panel.resignKey()
        }

        onRenameCommit?(index, newName)
        needsDisplay = true
    }

    func cancelRename() {
        isRenaming = false
        renameIndex = -1
        renameField.isHidden = true

        if let panel = window as? NSPanel {
            panel.resignKey()
        }

        onRenameCancel?()
        needsDisplay = true
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            commitRename()
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            cancelRename()
            return true
        }
        return false
    }
}
