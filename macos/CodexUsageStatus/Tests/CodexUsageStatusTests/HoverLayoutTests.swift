import AppKit
import Testing
@testable import CodexUsageStatus

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
}
