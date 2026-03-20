import Cocoa

class SwitcherPanel {
    let panel: NSPanel
    let contentView: SwitcherView
    var apps: [AppEntry] = []
    var selectedIndex: Int = 0

    // Cached app list in stable launch order (for Cmd+Ctrl+N bindings)
    var cachedApps: [AppEntry] = []
    // Track launch order by PID — new apps get appended, quit apps get removed
    var launchOrderPids: [pid_t] = []
    // MRU order — most recently activated first
    var mruPids: [pid_t] = []

    init() {
        let frame = NSRect(x: 0, y: 0, width: 600, height: 50)
        panel = NSPanel(
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
        panel.contentView = vibrancy

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
        apps = cachedApps
        guard !apps.isEmpty else { return }

        selectedIndex = -1
        contentView.update(apps: apps, selectedIndex: selectedIndex, showNumbers: true)

        positionPanel(appCount: apps.count)
        panel.orderFrontRegardless()
    }

    /// Cmd+< switcher — MRU order
    func show(reverse: Bool) {
        apps = getMRUApps()
        guard apps.count > 1 else { return }

        selectedIndex = reverse ? apps.count - 1 : 1
        contentView.update(apps: apps, selectedIndex: selectedIndex)

        positionPanel(appCount: apps.count)
        panel.orderFrontRegardless()
    }

    func cycleSelection(reverse: Bool) {
        guard apps.count > 1 else { return }
        if reverse {
            selectedIndex = (selectedIndex - 1 + apps.count) % apps.count
        } else {
            selectedIndex = (selectedIndex + 1) % apps.count
        }
        contentView.update(apps: apps, selectedIndex: selectedIndex)
    }

    /// Position panel centered horizontally, just below the menu bar / notch
    func positionPanel(appCount: Int) {
        let cellWidth: CGFloat = 52
        let width = CGFloat(appCount) * cellWidth + 20
        let height: CGFloat = 50
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let x = (screenFrame.width - width) / 2
        let y = visibleFrame.maxY - height + 8
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

    func commitAndHide() {
        if selectedIndex >= 0 && selectedIndex < apps.count {
            let app = apps[selectedIndex]
            app.nsApp.activate(options: .activateIgnoringOtherApps)
        }
        panel.orderOut(nil)
    }

    func hide() {
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
