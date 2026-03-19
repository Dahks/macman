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

    init() {
        let frame = NSRect(x: 0, y: 0, width: 600, height: 100)
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

        contentView = SwitcherView(frame: frame)
        panel.contentView = contentView

        refreshCache()
        startCacheTimer()

        let ws = NSWorkspace.shared
        ws.notificationCenter.addObserver(self, selector: #selector(appChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        ws.notificationCenter.addObserver(self, selector: #selector(appChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        ws.notificationCenter.addObserver(self, selector: #selector(appChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    @objc func appChanged(_ notification: Notification) {
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

        // Remove PIDs that are no longer running
        launchOrderPids.removeAll { !currentPids.contains($0) }

        // Append any new PIDs (preserves order of existing ones)
        for app in runningApps {
            if !launchOrderPids.contains(app.processIdentifier) {
                launchOrderPids.append(app.processIdentifier)
            }
        }

        // Build entries in launch order
        let appsByPid = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) })
        let entries = launchOrderPids.compactMap { pid -> AppEntry? in
            guard let nsApp = appsByPid[pid] else { return nil }
            return AppEntry(nsApp: nsApp)
        }

        // Pre-warm icon cache
        for entry in entries {
            _ = entry.cachedIcon
        }

        cachedApps = entries
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

    func show(reverse: Bool) {
        apps = cachedApps

        // Re-sort so current frontmost is first (for the Cmd+< switcher view)
        let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        apps.sort { a, b in
            if a.nsApp.processIdentifier == frontmostPid { return true }
            if b.nsApp.processIdentifier == frontmostPid { return false }
            return false
        }

        guard apps.count > 1 else { return }

        selectedIndex = reverse ? apps.count - 1 : 1
        contentView.update(apps: apps, selectedIndex: selectedIndex)

        let width = CGFloat(apps.count) * 80 + 20
        let height: CGFloat = 100
        let screenFrame = NSScreen.main?.frame ?? .zero
        let x = (screenFrame.width - width) / 2
        let y = (screenFrame.height - height) / 2
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

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

    func commitAndHide() {
        if selectedIndex < apps.count {
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
