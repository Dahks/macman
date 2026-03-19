import Cocoa

class SwitcherView: NSView {
    var apps: [AppEntry] = []
    var selectedIndex: Int = 0
    var showNumbers: Bool = false

    private let cornerRadius: CGFloat = 14
    private let selectionRadius: CGFloat = 10

    private let iconSize: CGFloat = 36
    private let cellWidth: CGFloat = 52
    private let padding: CGFloat = 10

    func update(apps: [AppEntry], selectedIndex: Int, showNumbers: Bool = false) {
        self.apps = apps
        self.selectedIndex = selectedIndex
        self.showNumbers = showNumbers
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor(white: 0.12, alpha: 0.85).setFill()
        bgPath.fill()

        for (index, app) in apps.enumerated() {
            let x = padding + CGFloat(index) * cellWidth
            let iconRect = NSRect(
                x: x + (cellWidth - iconSize) / 2,
                y: (bounds.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )

            // Selection highlight
            if index == selectedIndex {
                let selRect = NSRect(
                    x: x + 4,
                    y: (bounds.height - iconSize) / 2 - 6,
                    width: cellWidth - 8,
                    height: iconSize + 12
                )
                let selPath = NSBezierPath(roundedRect: selRect, xRadius: selectionRadius, yRadius: selectionRadius)
                NSColor(white: 1.0, alpha: 0.15).setFill()
                selPath.fill()
            }

            // App icon
            app.icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)

            // Number badge (top-right of icon) in overview mode
            if showNumbers && index < 9 {
                let numStr = "\(index + 1)" as NSString
                let badgeSize: CGFloat = 18
                let badgeRect = NSRect(
                    x: iconRect.maxX - badgeSize + 2,
                    y: iconRect.maxY - badgeSize + 2,
                    width: badgeSize,
                    height: badgeSize
                )
                let badgePath = NSBezierPath(ovalIn: badgeRect)
                NSColor(white: 0.0, alpha: 0.7).setFill()
                badgePath.fill()

                let numAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: NSColor.white,
                ]
                let numSize = numStr.size(withAttributes: numAttrs)
                let numX = badgeRect.midX - numSize.width / 2
                let numY = badgeRect.midY - numSize.height / 2
                numStr.draw(at: NSPoint(x: numX, y: numY), withAttributes: numAttrs)
            }

            // App name below icon (only for selected)
            if index == selectedIndex {
                let nameStr = app.name as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: NSColor.white,
                ]
                let nameSize = nameStr.size(withAttributes: attrs)
                let nameX = x + (cellWidth - nameSize.width) / 2
                let nameY: CGFloat = 4
                nameStr.draw(at: NSPoint(x: nameX, y: nameY), withAttributes: attrs)
            }
        }
    }
}
