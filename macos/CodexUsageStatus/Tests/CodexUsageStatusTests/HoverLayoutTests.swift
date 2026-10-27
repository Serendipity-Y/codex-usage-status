import AppKit
import Testing
@testable import CodexUsageStatus

@Test @MainActor func visiblePopoverResizesForFailureAndRecovery() async throws {
    _ = NSApplication.shared
    let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 40), styleMask: .borderless,
                        backing: .buffered, defer: false)
    let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
    host.contentView = anchor
    host.orderFront(nil)
    let controller = HoverCardViewController()
    let popover = NSPopover()
    popover.animates = false
    popover.contentViewController = controller
    popover.contentSize = HoverCardViewController.size
    defer { popover.close(); host.orderOut(nil) }
    controller.update(HoverPresentation(usage: nil, nextRefreshDate: nil, lastRefreshDate: nil,
        isRefreshing: false, refreshFailed: false))
    popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    for failed in [true, false] {
        controller.update(HoverPresentation(usage: nil, nextRefreshDate: nil, lastRefreshDate: nil,
            isRefreshing: false, refreshFailed: failed))
        popover.contentSize = controller.preferredContentSize
        try await Task.sleep(for: .milliseconds(50))
        let expected = HoverCardViewController.size.height + (failed ? 28 : 0)
        #expect(popover.isShown)
        #expect(popover.contentSize.height == expected)
        #expect(controller.view.frame.height == expected)
    }
}

@Test @MainActor func hoverCardStaysWhiteAndFitsFailureAndUnknownLabels() {
    let controller = HoverCardViewController()
    controller.update(HoverPresentation(usage: nil, nextRefreshDate: Date().addingTimeInterval(300),
        lastRefreshDate: nil, isRefreshing: false, refreshFailed: true))
    let view = controller.view
    view.appearance = NSAppearance(named: .darkAqua)
    view.layoutSubtreeIfNeeded()
    let color = view.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.usingColorSpace(.deviceRGB)
    #expect(color?.redComponent == 1)
    #expect(color?.greenComponent == 1)
    #expect(color?.blueComponent == 1)

    func fields(in node: NSView) -> [NSTextField] {
        node.subviews.flatMap { child in
            if let field = child as? NSTextField { return [field] }
            return fields(in: child)
        }
    }
    let labels = fields(in: view)
    #expect(labels.contains { $0.stringValue == "更新失败 · 上次记录" })
    #expect(labels.contains { $0.stringValue == "暂未提供" })
    for label in labels {
        let frame = label.convert(label.bounds, to: view)
        #expect(frame.minX >= 0 && frame.maxX <= view.bounds.maxX)
        #expect(frame.minY >= 0 && frame.maxY <= view.bounds.maxY)
        #expect(label.frame.width >= label.intrinsicContentSize.width)
    }

    controller.update(HoverPresentation(usage: nil, nextRefreshDate: Date().addingTimeInterval(120),
        lastRefreshDate: Date(), isRefreshing: false, refreshFailed: false))
    view.layoutSubtreeIfNeeded()
    let visibleText = fields(in: view).filter { !$0.isHidden }.map(\.stringValue)
    #expect(!visibleText.contains("Codex 额度"))
    #expect(!visibleText.contains("自动更新"))
    #expect(!visibleText.contains { $0.hasPrefix("更新于") || $0.hasPrefix("点击圆环") })
    #expect(controller.preferredContentSize.height == HoverCardViewController.size.height)

    for error in [FetchError.timeout, .authenticationRequired, .invalidOutput, .appServerError(-32000)] {
        controller.update(HoverPresentation(usage: nil, nextRefreshDate: nil,
            lastRefreshDate: Date().addingTimeInterval(-86400), isRefreshing: false, refreshFailed: true,
            failureDescription: error.briefDescription))
        view.layoutSubtreeIfNeeded()
        for label in fields(in: view).filter({ !$0.isHidden }) {
            let frame = label.convert(label.bounds, to: view)
            #expect(frame.minY >= 0 && frame.maxY <= view.bounds.maxY)
            #expect(label.frame.width >= label.intrinsicContentSize.width)
        }
    }
}
