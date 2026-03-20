import Cocoa

class WindowEntry {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let windowName: String
    let bounds: CGRect  // from CGWindowList, used to match AXUIElement windows

    init(windowID: CGWindowID, ownerPID: pid_t, ownerName: String, windowName: String, bounds: CGRect) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.windowName = windowName
        self.bounds = bounds
    }

    /// Returns the display label, checking overrides first, then windowName, then ownerName.
    func displayLabel(overrides: [CGWindowID: String]) -> String {
        if let override = overrides[windowID] {
            return override
        }
        if !windowName.isEmpty {
            return windowName
        }
        return ownerName
    }

    /// Fetch all on-screen windows (layer 0, non-empty owner, excludes self).
    static func fetchWindows() -> [WindowEntry] {
        let selfPID = ProcessInfo.processInfo.processIdentifier

        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var entries: [WindowEntry] = []
        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let ownerName = info[kCGWindowOwnerName as String] as? String, !ownerName.isEmpty else { continue }
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID != selfPID else { continue }
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID else { continue }

            let windowName = info[kCGWindowName as String] as? String ?? ""

            var bounds = CGRect.zero
            if let boundsDict = info[kCGWindowBounds as String] as? [String: Any] {
                let x = boundsDict["X"] as? CGFloat ?? 0
                let y = boundsDict["Y"] as? CGFloat ?? 0
                let w = boundsDict["Width"] as? CGFloat ?? 0
                let h = boundsDict["Height"] as? CGFloat ?? 0
                bounds = CGRect(x: x, y: y, width: w, height: h)
            }

            entries.append(WindowEntry(
                windowID: windowID,
                ownerPID: ownerPID,
                ownerName: ownerName,
                windowName: windowName,
                bounds: bounds
            ))
        }
        return entries
    }
}
