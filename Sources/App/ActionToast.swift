import AppKit

/// Small floating HUD under the menu bar: last action + undo button.
@MainActor
final class ActionToast {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    var onUndo: (() -> Void)?

    func show(title: String, detail: String) {
        hideWork?.cancel()
        panel?.close()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.hidesOnDeactivate = false

        let root = NSView(frame: panel.contentView!.bounds)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        root.layer?.cornerRadius = 10
        root.autoresizingMask = [.width, .height]

        let titleField = NSTextField(labelWithString: title)
        titleField.font = .systemFont(ofSize: 12, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false

        let detailField = NSTextField(labelWithString: detail)
        detailField.font = .systemFont(ofSize: 11)
        detailField.textColor = .secondaryLabelColor
        detailField.lineBreakMode = .byTruncatingMiddle
        detailField.translatesAutoresizingMaskIntoConstraints = false

        let undo = NSButton(title: "✕", target: self, action: #selector(undoTapped))
        undo.bezelStyle = .inline
        undo.isBordered = false
        undo.font = .systemFont(ofSize: 14, weight: .medium)
        undo.toolTip = "Undo"
        undo.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(titleField)
        root.addSubview(detailField)
        root.addSubview(undo)
        panel.contentView = root

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            titleField.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: undo.leadingAnchor, constant: -8),

            detailField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            detailField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 2),
            detailField.trailingAnchor.constraint(lessThanOrEqualTo: undo.leadingAnchor, constant: -8),
            detailField.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),

            undo.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            undo.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            undo.widthAnchor.constraint(equalToConstant: 28),
            undo.heightAnchor.constraint(equalToConstant: 28),
        ])

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - 180
            let y = frame.maxY - 64
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in
            self?.panel?.close()
            self?.panel = nil
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel?.close()
        panel = nil
    }

    @objc private func undoTapped() {
        hide()
        onUndo?()
    }
}
