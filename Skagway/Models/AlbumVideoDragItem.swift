import AppKit
import SwiftUI

enum AlbumReorderPasteboard {
    static let prefix = "skagway-album-video:"
    static let nsType = NSPasteboard.PasteboardType("com.machiilabs.skagway.album-video")

    static func payload(videoId: String) -> String {
        prefix + videoId
    }

    static func videoId(from payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let id = String(trimmed.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }

    static func videoId(from pasteboard: NSPasteboard) -> String? {
        if let raw = pasteboard.string(forType: nsType) ?? pasteboard.string(forType: .string) {
            return videoId(from: raw)
        }
        return nil
    }
}

/// True while an album-reorder drag session is in flight so drop targets can receive the drag
/// without stealing normal clicks.
enum AlbumDragSession {
    static var isActive = false
}

/// Full-card AppKit drag source + drop target. SwiftUI `.onDrag` / `.draggable` do not start a
/// session on macOS grid cells (tap/selection wins). Clicks with no movement still select.
struct AlbumReorderInteractionOverlay: NSViewRepresentable {
    var videoId: String
    var title: String
    var onClick: (NSEvent.ModifierFlags) -> Void
    var onDoubleClick: () -> Void
    var onTargeted: (Bool) -> Void
    var onReorder: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AlbumReorderInteractionView {
        let view = AlbumReorderInteractionView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        apply(context.coordinator)
        return view
    }

    func updateNSView(_ nsView: AlbumReorderInteractionView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.view = nsView
        apply(context.coordinator)
        nsView.videoId = videoId
        nsView.dragTitle = title
    }

    private func apply(_ coordinator: Coordinator) {
        coordinator.videoId = videoId
        coordinator.dragTitle = title
        coordinator.onClick = onClick
        coordinator.onDoubleClick = onDoubleClick
        coordinator.onTargeted = onTargeted
        coordinator.onReorder = onReorder
    }

    final class Coordinator {
        var videoId = ""
        var dragTitle = ""
        var onClick: ((NSEvent.ModifierFlags) -> Void)?
        var onDoubleClick: (() -> Void)?
        var onTargeted: ((Bool) -> Void)?
        var onReorder: ((String) -> Void)?
        weak var view: AlbumReorderInteractionView?
    }
}

final class AlbumReorderInteractionView: NSView, NSDraggingSource {
    var videoId: String = ""
    var dragTitle: String = ""
    weak var coordinator: AlbumReorderInteractionOverlay.Coordinator?

    private var mouseDownPoint: NSPoint?
    private var startedDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes([AlbumReorderPasteboard.nsType, .string])
    }

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Left-button tracking for click-vs-drag. Other events (right-click, hover, Finder file
    /// drops) fall through to SwiftUI. Album-reorder drops are claimed while a session is active.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if AlbumDragSession.isActive { return self }
        guard let event = NSApp.currentEvent else { return nil }
        switch event.type {
        case .leftMouseDown:
            return self
        case .leftMouseDragged, .leftMouseUp:
            // Only continue a click we started — Finder file-drags are also leftMouseDragged.
            return mouseDownPoint != nil ? self : nil
        default:
            return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        startedDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !startedDrag else { return }
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        if hypot(dx, dy) > 6 {
            startedDrag = true
            beginAlbumDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let wasDrag = startedDrag
        mouseDownPoint = nil
        startedDrag = false
        guard !wasDrag else { return }
        if event.clickCount >= 2 {
            coordinator?.onDoubleClick?()
        } else {
            coordinator?.onClick?(event.modifierFlags)
        }
    }

    private func beginAlbumDrag(with event: NSEvent) {
        let id = coordinator?.videoId ?? videoId
        let title = coordinator?.dragTitle ?? dragTitle
        let payload = AlbumReorderPasteboard.payload(videoId: id)
        let pbItem = NSPasteboardItem()
        pbItem.setString(payload, forType: AlbumReorderPasteboard.nsType)
        pbItem.setString(payload, forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: pbItem)
        let preview = dragPreviewImage(title: title)
        draggingItem.setDraggingFrame(bounds, contents: preview)
        AlbumDragSession.isActive = true
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func dragPreviewImage(title: String) -> NSImage {
        let size = NSSize(width: min(max(bounds.width, 120), 220), height: 36)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.controlAccentColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 8, yRadius: 8).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let text = title as NSString
        let textSize = text.size(withAttributes: attrs)
        let origin = NSPoint(
            x: 10,
            y: max(0, (size.height - textSize.height) / 2)
        )
        text.draw(in: NSRect(origin: origin, size: NSSize(width: size.width - 20, height: textSize.height)),
                  withAttributes: attrs)
        image.unlockFocus()
        return image
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        AlbumDragSession.isActive = false
        coordinator?.onTargeted?(false)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard AlbumReorderPasteboard.videoId(from: sender.draggingPasteboard) != nil else { return [] }
        coordinator?.onTargeted?(true)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        coordinator?.onTargeted?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        AlbumReorderPasteboard.videoId(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        coordinator?.onTargeted?(false)
        guard let draggedId = AlbumReorderPasteboard.videoId(from: sender.draggingPasteboard) else { return false }
        coordinator?.onReorder?(draggedId)
        return true
    }
}

/// Visual-only affordance drawn on the thumbnail. Dragging is handled by `AlbumReorderInteractionOverlay`.
struct AlbumReorderHandleBadge: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .padding(8)
            .allowsHitTesting(false)
            .help("Drag this card to reorder the album")
    }
}
