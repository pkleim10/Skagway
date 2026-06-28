import AppKit

/// Container that clips its hosted view. When frozen, the hosted view keeps a fixed width
/// regardless of how the container is resized by the split view, producing a clipping effect.
final class ClippingContainer: NSView {
    private(set) var isFrozen = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = true
    }

    func freeze() {
        guard !isFrozen, let hosted = subviews.first else { return }
        isFrozen = true
        let w = hosted.frame.width
        hosted.translatesAutoresizingMaskIntoConstraints = true
        hosted.autoresizingMask = [.height]
        hosted.frame = NSRect(x: 0, y: 0, width: w, height: bounds.height)
    }

    /// While frozen, snap the hosted view's width to the container's current width so its content (e.g. the
    /// grid) reflows to fill the new size. Used after a debounced splitter drag during detail-pane playback,
    /// where live reflow on every drag frame would be expensive — the view stays frozen at the new width.
    func reflowToCurrentWidth() {
        guard isFrozen, let hosted = subviews.first else { return }
        let w = bounds.width
        guard w > 0, abs(hosted.frame.width - w) > 0.5 else { return }
        hosted.frame = NSRect(x: 0, y: 0, width: w, height: bounds.height)
        hosted.layoutSubtreeIfNeeded()
    }

    func unfreeze() {
        guard isFrozen, let hosted = subviews.first else { return }
        isFrozen = false
        hosted.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosted.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosted.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosted.topAnchor.constraint(equalTo: topAnchor),
            hosted.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        if isFrozen, let hosted = subviews.first {
            hosted.frame.size.height = bounds.height
        } else {
            super.resizeSubviews(withOldSize: oldSize)
        }
    }
}
