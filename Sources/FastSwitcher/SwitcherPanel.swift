import Cocoa
import ApplicationServices

enum ViewMode {
    case icon
    case tmux
}

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

class SwitcherPanel {
    let panel: KeyablePanel
    let contentView: SwitcherView
    let tmuxView: TmuxBarView
    var apps: [AppEntry] = []
    var selectedIndex: Int = 0
    var wasOverviewOpen: Bool = false

    var viewMode: ViewMode = .icon

    // Cached app list in stable launch order (for Cmd+Ctrl+N bindings)
    var cachedApps: [AppEntry] = []
    // Track launch order by PID — new apps get appended, quit apps get removed
    var launchOrderPids: [pid_t] = []
    // MRU order — most recently activated first
    var mruPids: [pid_t] = []

    // Window tracking for tmux mode
    var cachedWindows: [WindowEntry] = []
    var windowOrder: [CGWindowID] = []  // stable order, like launchOrderPids
    var windowNameOverrides: [CGWindowID: String] = [:]
    var activeWindowID: CGWindowID = 0
    var previousWindowID: CGWindowID = 0

    var isRenaming: Bool { tmuxView.isRenaming }

    init() {
        let frame = NSRect(x: 0, y: 0, width: 600, height: 50)
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

        // Vibrancy background matching the menu bar
        let vibrancy = NSVisualEffectView(frame: frame)
        vibrancy.material = .menu
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 14
        vibrancy.layer?.masksToBounds = true
        vibrancy.maskImage = SwitcherPanel.roundedMask(size: frame.size, radius: 14)

        contentView = SwitcherView(frame: frame)
        contentView.autoresizingMask = [.width, .height]
        vibrancy.addSubview(contentView)

        tmuxView = TmuxBarView(frame: frame)
        tmuxView.autoresizingMask = [.width, .height]
        tmuxView.isHidden = true
        vibrancy.addSubview(tmuxView)

        panel.contentView = vibrancy

        // Rename callbacks
        tmuxView.onRenameCommit = { [weak self] index, newName in
            self?.commitRename(index: index, newName: newName)
        }
        tmuxView.onRenameCancel = {
            // Nothing extra needed
        }

        refreshCache()
        startCacheTimer()

        let ws = NSWorkspace.shared
        ws.notificationCenter.addObserver(self, selector: #selector(appLaunchedOrQuit), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        ws.notificationCenter.addObserver(self, selector: #selector(appLaunchedOrQuit), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        ws.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    @objc func appLaunchedOrQuit(_ notification: Notification) {
        refreshCache()
    }

    @objc func appActivated(_ notification: Notification) {
        // Update MRU order: move activated app to front
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            let pid = app.processIdentifier
            mruPids.removeAll { $0 == pid }
            mruPids.insert(pid, at: 0)
        }
        refreshCache()
    }

    func startCacheTimer() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshCache()
        }
    }

    func refreshCache() {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }

        let currentPids = Set(runningApps.map { $0.processIdentifier })

        // Clean up dead PIDs from both lists
        launchOrderPids.removeAll { !currentPids.contains($0) }
        mruPids.removeAll { !currentPids.contains($0) }

        // Append any new PIDs to launch order
        for app in runningApps {
            if !launchOrderPids.contains(app.processIdentifier) {
                launchOrderPids.append(app.processIdentifier)
            }
            // Also add to MRU if not tracked yet (at the end)
            if !mruPids.contains(app.processIdentifier) {
                mruPids.append(app.processIdentifier)
            }
        }

        // Build entries in launch order
        let appsByPid = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) })
        let entries = launchOrderPids.compactMap { pid -> AppEntry? in
            guard let nsApp = appsByPid[pid] else { return nil }
            return AppEntry(nsApp: nsApp)
        }

        for entry in entries {
            _ = entry.cachedIcon
        }

        cachedApps = entries

        // Also fetch windows for tmux mode
        let windows = WindowEntry.fetchWindows()
        let currentWindowIDs = Set(windows.map { $0.windowID })

        // Prune stale entries
        windowOrder.removeAll { !currentWindowIDs.contains($0) }
        windowNameOverrides = windowNameOverrides.filter { currentWindowIDs.contains($0.key) }

        // Append new windows to stable order
        for win in windows {
            if !windowOrder.contains(win.windowID) {
                windowOrder.append(win.windowID)
            }
        }

        // Build cachedWindows in stable order
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowID, $0) })
        cachedWindows = windowOrder.compactMap { windowsByID[$0] }

        // Track active window ID changes (first in CGWindowList = frontmost)
        if let frontWindow = windows.first {
            if frontWindow.windowID != activeWindowID {
                previousWindowID = activeWindowID
                activeWindowID = frontWindow.windowID
            }
        }

        // Live-update the visible bar
        if wasOverviewOpen && !tmuxView.isRenaming {
            switch viewMode {
            case .icon:
                apps = cachedApps
                contentView.update(apps: apps, selectedIndex: selectedIndex, showNumbers: true)
                positionPanel(appCount: apps.count)
            case .tmux:
                updateTmuxCells()
                positionTmuxPanel()
            }
        }
    }

    /// Get apps in MRU order
    func getMRUApps() -> [AppEntry] {
        let appsByPid = Dictionary(uniqueKeysWithValues: cachedApps.map { ($0.nsApp.processIdentifier, $0) })
        return mruPids.compactMap { appsByPid[$0] }
    }

    /// Get apps in launch order (for Cmd+Ctrl+N)
    func appAtIndex(_ index: Int) -> AppEntry? {
        guard index >= 0 && index < cachedApps.count else { return nil }
        return cachedApps[index]
    }

    func activateAppAtIndex(_ index: Int) {
        guard let app = appAtIndex(index) else { return }
        app.nsApp.activate(options: .activateIgnoringOtherApps)
    }

    /// Toggle overview — shows all apps in launch order with number labels
    func showOverview() {
        wasOverviewOpen = true

        switch viewMode {
        case .icon:
            apps = cachedApps
            guard !apps.isEmpty else { return }
            selectedIndex = -1
            contentView.isHidden = false
            tmuxView.isHidden = true
            contentView.update(apps: apps, selectedIndex: selectedIndex, showNumbers: true)
            positionPanel(appCount: apps.count)

        case .tmux:
            guard !cachedWindows.isEmpty else { return }
            selectedIndex = -1
            contentView.isHidden = true
            tmuxView.isHidden = false
            updateTmuxCells()
            positionTmuxPanel()
        }

        panel.orderFrontRegardless()
    }

    /// Cmd+< switcher — MRU order
    func show(reverse: Bool) {
        switch viewMode {
        case .icon:
            apps = getMRUApps()
            guard apps.count > 1 else { return }
            selectedIndex = reverse ? apps.count - 1 : 1
            contentView.isHidden = false
            tmuxView.isHidden = true
            contentView.update(apps: apps, selectedIndex: selectedIndex)
            positionPanel(appCount: apps.count)

        case .tmux:
            apps = getMRUApps()
            guard apps.count > 1 else { return }
            selectedIndex = reverse ? apps.count - 1 : 1
            contentView.isHidden = true
            tmuxView.isHidden = false
            // In MRU mode with tmux, show apps (not windows) as text cells
            let cells = apps.enumerated().map { (i, app) -> TmuxBarView.Cell in
                TmuxBarView.Cell(
                    index: i,
                    label: app.name,
                    isActive: false,
                    isPrevious: false,
                    icon: app.icon
                )
            }
            tmuxView.update(cells: cells, selectedIndex: selectedIndex)
            positionTmuxPanel()
        }

        panel.orderFrontRegardless()
    }

    func cycleSelection(reverse: Bool) {
        guard apps.count > 1 else { return }
        if reverse {
            selectedIndex = (selectedIndex - 1 + apps.count) % apps.count
        } else {
            selectedIndex = (selectedIndex + 1) % apps.count
        }
        switch viewMode {
        case .icon:
            contentView.update(apps: apps, selectedIndex: selectedIndex)
        case .tmux:
            tmuxView.selectedIndex = selectedIndex
            tmuxView.needsDisplay = true
        }
    }

    /// Position panel centered horizontally, just below the menu bar / notch
    func positionPanel(appCount: Int) {
        let cellWidth: CGFloat = 52
        let width = CGFloat(appCount) * cellWidth + 20
        let height: CGFloat = 50
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame
        let x = (screenFrame.width - width) / 2
        let y: CGFloat = -8
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        // Update the vibrancy mask to match new size
        if let vibrancy = panel.contentView as? NSVisualEffectView {
            vibrancy.maskImage = SwitcherPanel.roundedMask(size: NSSize(width: width, height: height), radius: 14)
        }
    }

    static func roundedMask(size: NSSize, radius: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        return image
    }

    // MARK: - Tmux View Helpers

    func updateTmuxCells() {
        let appsByPid = Dictionary(uniqueKeysWithValues: cachedApps.map { ($0.nsApp.processIdentifier, $0) })
        let cells = cachedWindows.enumerated().map { (i, win) -> TmuxBarView.Cell in
            TmuxBarView.Cell(
                index: i + 1,  // 1-based to match Ctrl+1-9
                label: win.displayLabel(overrides: windowNameOverrides),
                isActive: win.windowID == activeWindowID,
                isPrevious: win.windowID == previousWindowID,
                icon: appsByPid[win.ownerPID]?.icon
            )
        }
        tmuxView.update(cells: cells, selectedIndex: selectedIndex)
    }

    func positionTmuxPanel() {
        let width = tmuxView.requiredWidth()
        let height: CGFloat = 16
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame
        let x = (screenFrame.width - width) / 2
        let y: CGFloat = -3
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        if let vibrancy = panel.contentView as? NSVisualEffectView {
            vibrancy.maskImage = SwitcherPanel.roundedMask(size: NSSize(width: width, height: height), radius: 10)
        }
    }

    // MARK: - View Mode Cycling

    func cycleViewMode() {
        switch viewMode {
        case .icon: viewMode = .tmux
        case .tmux: viewMode = .icon
        }
        // If overview is showing, refresh it in the new mode
        if wasOverviewOpen {
            refreshCache()
            showOverview()
        }
    }

    // MARK: - Rename (tmux mode)

    func beginRenameMode() {
        guard viewMode == .tmux, !cachedWindows.isEmpty else { return }
        // Ensure the tmux bar is visible
        if !wasOverviewOpen {
            showOverview()
        }
        // Find the active window index, or use 0
        let index = cachedWindows.firstIndex(where: { $0.windowID == activeWindowID }) ?? 0
        tmuxView.beginRename(at: index)
    }

    func commitRename(index: Int, newName: String) {
        guard index >= 0 && index < cachedWindows.count else { return }
        let windowID = cachedWindows[index].windowID
        if newName.isEmpty {
            windowNameOverrides.removeValue(forKey: windowID)
        } else {
            windowNameOverrides[windowID] = newName
        }
        updateTmuxCells()
        positionTmuxPanel()
    }

    // MARK: - Window Activation

    func activateWindow(_ entry: WindowEntry) {
        // First activate the owning app
        if let app = NSRunningApplication(processIdentifier: entry.ownerPID) {
            app.activate(options: .activateIgnoringOtherApps)
        }

        // Then raise the specific window via AXUIElement, matching by position+size
        let appElement = AXUIElementCreateApplication(entry.ownerPID)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return }

        for axWindow in axWindows {
            // Get AX window position and size
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
                  AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success
            else { continue }

            var pos = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

            // Match against the CGWindowList bounds (tolerance for rounding)
            if abs(pos.x - entry.bounds.origin.x) < 2
                && abs(pos.y - entry.bounds.origin.y) < 2
                && abs(size.width - entry.bounds.width) < 2
                && abs(size.height - entry.bounds.height) < 2 {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                break
            }
        }
    }

    func activateWindowAtIndex(_ index: Int) {
        guard index >= 0 && index < cachedWindows.count else { return }
        activateWindow(cachedWindows[index])
    }

    func commitAndHide() {
        if selectedIndex >= 0 && selectedIndex < apps.count {
            let app = apps[selectedIndex]
            app.nsApp.activate(options: .activateIgnoringOtherApps)
        }
        panel.orderOut(nil)
    }

    func hide() {
        wasOverviewOpen = false
        panel.orderOut(nil)
    }
}

// MARK: - AppEntry

class AppEntry {
    let nsApp: NSRunningApplication
    lazy var cachedIcon: NSImage = {
        nsApp.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }()

    var name: String {
        nsApp.localizedName ?? "Unknown"
    }

    var icon: NSImage {
        cachedIcon
    }

    init(nsApp: NSRunningApplication) {
        self.nsApp = nsApp
    }
}
