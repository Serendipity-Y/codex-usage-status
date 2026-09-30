import AppKit

@MainActor
final class HoverCardViewController: NSViewController {
    static let size = NSSize(width: 320, height: 196)
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private let credits = NSTextField(labelWithString: "暂未提供")
    private let fiveHour = NSTextField(labelWithString: "暂未提供")
    private let weekly = NSTextField(labelWithString: "暂未提供")
    private let refresh = NSTextField(labelWithString: "等待首次刷新")
    private let status = NSTextField(labelWithString: "")

    override func loadView() {
        let card = HoverCardView(frame: NSRect(origin: .zero, size: Self.size))
        card.onEnter = { [weak self] in self?.onEnter?() }
        card.onExit = { [weak self] in self?.onExit?() }
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 10
        view = card

        style(credits, size: 28, weight: .semibold)
        let creditRow = row(label("可用重置机会", size: 13, weight: .medium, color: .darkGray), credits)
        creditRow.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let separator = NSBox()
        separator.boxType = .separator
        for value in [fiveHour, weekly, refresh] {
            style(value, size: 13, weight: .medium)
            value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        }
        let details = NSStackView(views: [
            row(label("5 小时额度恢复", size: 12.5, color: .darkGray), fiveHour),
            row(label("每周额度恢复", size: 12.5, color: .darkGray), weekly),
            row(label("下次数据刷新", size: 12.5, color: .darkGray), refresh)])
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 14
        for child in details.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true
        }
        style(status, size: 10)
        status.isHidden = true

        let stack = NSStackView(views: [creditRow, separator, details, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -20),
        ])
        for child in stack.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    func update(_ presentation: HoverPresentation) {
        _ = view
        credits.stringValue = presentation.resetCredits
        fiveHour.stringValue = presentation.fiveHourReset
        weekly.stringValue = presentation.weeklyReset
        refresh.stringValue = presentation.nextRefresh
        status.stringValue = presentation.isStale ? presentation.status : ""
        status.isHidden = !presentation.isStale
        status.textColor = NSColor(calibratedRed: 0.65, green: 0.32, blue: 0.05, alpha: 1)
        preferredContentSize = NSSize(width: Self.size.width, height: Self.size.height + (presentation.isStale ? 28 : 0))
        view.setFrameSize(preferredContentSize)
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor? = nil) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        style(field, size: size, weight: weight, color: color)
        return field
    }

    private func style(_ field: NSTextField, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor? = nil) {
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color ?? NSColor(calibratedWhite: 0.13, alpha: 1)
        field.lineBreakMode = .byClipping
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func row(_ left: NSView, _ right: NSView) -> NSStackView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [left, spacer, right])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }
}

@MainActor
private final class HoverCardView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
