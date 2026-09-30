import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
    private let displayStyleItem = NSMenuItem(title: "Display Style", action: nil, keyEquivalent: "")
    private let displayStyleMenu = NSMenu()
    private let doubleRingItem = NSMenuItem(title: BadgeStyle.doubleRing.menuTitle, action: #selector(selectDoubleRingStyle), keyEquivalent: "")
    private let largeReadoutItem = NSMenuItem(title: BadgeStyle.largeReadout.menuTitle, action: #selector(selectLargeReadoutStyle), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")

    private var timer: Timer?
    private var isRefreshing = false
    private let refreshInterval = configuredRefreshInterval()
    private var badgeStyle = BadgeStyle.load()
    private var lastUsage: UsageSummary?
    private var lastRefreshDate: Date?
    private var lastError: Error?
    private var nextRefreshDate: Date?
    private var buttonTrackingArea: NSTrackingArea?
    private var hoverShowWork: DispatchWorkItem?
    private var hoverHideWork: DispatchWorkItem?
    private var menuIsOpen = false
    private var previewShown = false
    private lazy var hoverCard: HoverCardViewController = {
        let card = HoverCardViewController()
        card.onEnter = { [weak self] in self?.hoverHideWork?.cancel() }
        card.onExit = { [weak self] in self?.scheduleHoverClose() }
        return card
    }()
    private lazy var hoverPopover: NSPopover = {
        let popover = NSPopover()
        popover.contentViewController = hoverCard
        popover.contentSize = HoverCardViewController.size
        popover.appearance = NSAppearance(named: .aqua)
        popover.behavior = .applicationDefined
        popover.animates = false
        return popover
    }()

    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--show-hover") {
            FileHandle.standardOutput.write(Data("UI launch callback received\n".utf8))
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem.length = UsageBadgeRenderer.statusItemLength(for: badgeStyle)

        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = nil
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
            button.addTrackingArea(area)
            buttonTrackingArea = area
        }
        renderCurrentBadge()

        refreshItem.target = self
        menu.addItem(refreshItem)

        doubleRingItem.target = self
        largeReadoutItem.target = self
        displayStyleMenu.addItem(doubleRingItem)
        displayStyleMenu.addItem(largeReadoutItem)
        displayStyleItem.submenu = displayStyleMenu
        menu.addItem(displayStyleItem)
        updateStyleMenuState()

        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        menu.delegate = self
        refresh()
    }

    @objc(mouseEntered:) private func statusMouseEntered(_ event: NSEvent) {
        hoverHideWork?.cancel()
        hoverShowWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.showHoverPopover() }
        hoverShowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    @objc(mouseExited:) private func statusMouseExited(_ event: NSEvent) {
        hoverShowWork?.cancel()
        scheduleHoverClose()
    }

    private func scheduleHoverClose() {
        hoverHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hoverPopover.close() }
        hoverHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func showHoverPopover() {
        guard !menuIsOpen, let button = statusItem.button, button.window != nil else { return }
        updateHoverCard()
        hoverPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if CommandLine.arguments.contains("--show-hover") {
            FileHandle.standardOutput.write(Data("Hover visible: \(hoverPopover.isShown)\n".utf8))
            if let path = ProcessInfo.processInfo.environment["CODEX_USAGE_PREVIEW_PNG"] {
                hoverCard.view.layoutSubtreeIfNeeded()
                if let bitmap = hoverCard.view.bitmapImageRepForCachingDisplay(in: hoverCard.view.bounds) {
                    hoverCard.view.cacheDisplay(in: hoverCard.view.bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path))
                    }
                }
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        hoverShowWork?.cancel()
        hoverHideWork?.cancel()
        hoverPopover.close()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    private func updateHoverCard() {
        hoverCard.update(HoverPresentation(usage: lastUsage, nextRefreshDate: nextRefreshDate,
            lastRefreshDate: lastRefreshDate, isRefreshing: isRefreshing, refreshFailed: lastError != nil))
        hoverPopover.contentSize = hoverCard.preferredContentSize
    }

    @objc private func refreshFromMenu() {
        refresh()
    }

    @objc private func timerDidFire() {
        refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func selectDoubleRingStyle() {
        setBadgeStyle(.doubleRing)
    }

    @objc private func selectLargeReadoutStyle() {
        setBadgeStyle(.largeReadout)
    }

    @objc private func showSettings() {
        let status: String
        if let lastError {
            status = "Last refresh failed: \(lastError.localizedDescription)"
        } else if let lastUsage {
            status = lastUsage.verboseTitle
        } else {
            status = "Waiting for first refresh"
        }

        let lastRefresh = lastRefreshDate.map { dateFormatter.string(from: $0) } ?? "Never"
        let message = """
        \(status)

        Display style: \(badgeStyle.menuTitle)
        Refresh interval: \(Int(refreshInterval)) seconds
        Failure retry: \(Int(AppConfig.errorRetryInterval)) seconds
        Last refresh: \(lastRefresh)
        Data source: local Codex app-server
        """

        let alert = NSAlert()
        alert.messageText = "Codex Usage Status"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func setBadgeStyle(_ style: BadgeStyle) {
        guard badgeStyle != style else {
            return
        }
        badgeStyle = style
        badgeStyle.save()
        updateStyleMenuState()
        renderCurrentBadge()
    }

    private func updateStyleMenuState() {
        doubleRingItem.state = badgeStyle == .doubleRing ? .on : .off
        largeReadoutItem.state = badgeStyle == .largeReadout ? .on : .off
    }

    private func refresh() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        timer?.invalidate()
        timer = nil
        nextRefreshDate = nil
        refreshItem.isEnabled = false
        refreshItem.title = "Refreshing..."
        updateHoverCard()

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let usage = try await CodexUsageFetcher.fetch()
                self.isRefreshing = false
                self.refreshItem.isEnabled = true
                self.refreshItem.title = "Refresh"
                self.applyUsage(usage)
                self.scheduleNextRefresh(after: self.refreshInterval)
            } catch {
                self.isRefreshing = false
                self.refreshItem.isEnabled = true
                self.refreshItem.title = "Refresh"
                self.applyError(error)
                self.scheduleNextRefresh(after: AppConfig.errorRetryInterval)
            }
        }
    }

    private func scheduleNextRefresh(after seconds: TimeInterval) {
        timer?.invalidate()
        let scheduled = Timer(fireAt: Date(timeIntervalSinceNow: seconds), interval: 0,
            target: self, selector: #selector(timerDidFire), userInfo: nil, repeats: false)
        timer = scheduled
        nextRefreshDate = scheduled.fireDate
        RunLoop.main.add(scheduled, forMode: .common)
        updateHoverCard()
        if CommandLine.arguments.contains("--show-hover"), !previewShown {
            previewShown = true
            showHoverPopover()
        }
    }

    private func applyUsage(_ usage: UsageSummary) {
        lastUsage = usage
        lastRefreshDate = Date()
        lastError = nil
        renderCurrentBadge()
    }

    private func applyError(_ error: Error) {
        lastError = error
        renderCurrentBadge()
    }

    private func renderCurrentBadge() {
        statusItem.length = UsageBadgeRenderer.statusItemLength(for: badgeStyle)
        if let button = statusItem.button {
            button.title = ""
            button.toolTip = nil

            if let lastError {
                button.image = UsageBadgeRenderer.errorImage(style: badgeStyle, appearance: button.effectiveAppearance)
                button.setAccessibilityLabel("Codex 额度更新失败：\(lastError.localizedDescription)")
            } else if let lastUsage {
                button.image = UsageBadgeRenderer.image(for: lastUsage, style: badgeStyle, appearance: button.effectiveAppearance)
                button.setAccessibilityLabel(lastUsage.verboseTitle)
            } else {
                button.image = UsageBadgeRenderer.placeholderImage(style: badgeStyle, appearance: button.effectiveAppearance)
                button.setAccessibilityLabel("Codex 额度正在读取")
            }
        }
    }
}
