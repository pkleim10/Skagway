import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Hosts inline playback in a separate window so the main library window stays normal.
/// Edge-to-edge mode uses a borderless window at `NSScreen.frame` (no `toggleFullScreen` space animation).
@MainActor
final class FullscreenInlinePlayerWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let playerView = AVPlayerView()
    private var subtitleHost: NSHostingView<SubtitleOverlayContainer>?
    /// Bottom-strip timeline with normal hit testing (not a full-screen pass-through overlay).
    private var timelineHost: NSHostingView<FullscreenTimelineOverlay>?
    private var closeButton: NSButton?
    private var chrome = FullscreenChromeController()
    private var onEnded: (() -> Void)?
    private var didEnd = false
    private var keyDownMonitor: Any?
    private var mouseMonitor: Any?
    private var savedPresentationOptions: NSApplication.PresentationOptions = []
    private var didApplyPresentationOptions = false
    /// Bumps on every show/hide so delayed hide-completion can’t clobber a newer reveal.
    private var visibilityGeneration = 0

    private static let timelineStripHeight: CGFloat = PlaybackTimelineBar.barHeight + 100

    func present(
        player: AVPlayer,
        title: String,
        startWindowInFullscreen: Bool,
        subtitleTrack: SubtitleTrack,
        viewModel: LibraryViewModel,
        onEnded: @escaping () -> Void
    ) {
        self.onEnded = onEnded

        playerView.player = player
        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = !startWindowInFullscreen

        let host = NSHostingView(rootView: SubtitleOverlayContainer(track: subtitleTrack))
        self.subtitleHost = host

        let timeline = NSHostingView(rootView: FullscreenTimelineOverlay(viewModel: viewModel))
        timeline.wantsLayer = true
        timeline.layer?.backgroundColor = NSColor.clear.cgColor
        timeline.alphaValue = 1
        timeline.isHidden = false
        self.timelineHost = timeline

        chrome.onVisibilityChange = { [weak self] visible in
            self?.applyTimelineVisibility(visible)
        }

        if startWindowInFullscreen {
            presentEdgeToEdge(title: title)
        } else {
            presentTitledWindow(title: title)
        }
    }

    private func presentEdgeToEdge(title: String) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            presentTitledWindow(title: title)
            return
        }

        let frame = screen.frame
        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))

        embedFullSize(playerView, in: content)
        if let host = subtitleHost {
            embedFullSizePassThrough(host, in: content)
        }
        if let timeline = timelineHost {
            embedBottomStrip(timeline, in: content, height: Self.timelineStripHeight)
        }

        let close = makeCloseButton()
        close.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(close)
        NSLayoutConstraint.activate([
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            close.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28),
        ])
        self.closeButton = close

        let w = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.title = title
        w.contentView = content
        w.delegate = self
        w.isReleasedWhenClosed = false
        w.isOpaque = true
        w.backgroundColor = .black
        w.isMovable = false
        w.acceptsMouseMovedEvents = true
        w.setFrame(frame, display: true)
        window = w
        w.makeKeyAndOrderFront(nil)

        savedPresentationOptions = NSApplication.shared.presentationOptions
        NSApplication.shared.presentationOptions = [.hideMenuBar, .hideDock]
        didApplyPresentationOptions = true

        installEventMonitors()
        // Start visible; hide only after idle away from the transport.
        chrome.pointerMoved(overTimeline: false)
        applyTimelineVisibility(true)
    }

    private func presentTitledWindow(title: String) {
        playerView.showsFullScreenToggleButton = true
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        embedFullSize(playerView, in: content)
        if let host = subtitleHost {
            embedFullSizePassThrough(host, in: content)
        }
        if let timeline = timelineHost {
            embedBottomStrip(timeline, in: content, height: Self.timelineStripHeight)
        }

        let w = NSWindow(
            contentRect: content.bounds,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = title
        w.contentView = content
        w.delegate = self
        w.isReleasedWhenClosed = false
        w.acceptsMouseMovedEvents = true
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)

        installEventMonitors()
        chrome.pointerMoved(overTimeline: false)
        applyTimelineVisibility(true)
    }

    private func embedFullSize(_ child: NSView, in parent: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = true
        child.frame = parent.bounds
        child.autoresizingMask = [.width, .height]
        parent.addSubview(child)
    }

    private func embedFullSizePassThrough(_ child: NSView, in parent: NSView) {
        let wrap = PassThroughView(frame: parent.bounds)
        wrap.autoresizingMask = [.width, .height]
        child.frame = wrap.bounds
        child.autoresizingMask = [.width, .height]
        wrap.addSubview(child)
        parent.addSubview(wrap)
    }

    private func embedBottomStrip(_ child: NSView, in parent: NSView, height: CGFloat) {
        child.translatesAutoresizingMaskIntoConstraints = true
        child.frame = NSRect(x: 0, y: 0, width: parent.bounds.width, height: height)
        child.autoresizingMask = [.width, .maxYMargin]
        parent.addSubview(child)
    }

    private func installEventMonitors() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.window else { return event }
            if event.keyCode == 53 ||
               (event.keyCode == 3 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control, .command]) {
                self.closeWindow()
                return nil
            }
            return event
        }

        // Local monitor sees moves even when AVPlayerView is the hit target (view tracking often doesn’t).
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            guard let self else { return event }
            guard event.window === self.window else { return event }
            let location = event.locationInWindow
            // Dispatch async onto the main actor queue — the monitor is not MainActor-isolated,
            // but AppKit delivers these on the main thread; async avoids re-entrancy into SwiftUI.
            DispatchQueue.main.async {
                self.handleMouseActivity(locationInWindow: location)
            }
            return event
        }
    }

    private func handleMouseActivity(locationInWindow: CGPoint) {
        let overTimeline: Bool
        if let timelineHost, !timelineHost.isHidden {
            overTimeline = timelineHost.frame.contains(locationInWindow)
        } else if let timelineHost {
            // Strip is hidden — still treat the bottom strip region as “over timeline” for reveal,
            // but more importantly any move should reveal. Use the last known frame.
            overTimeline = timelineHost.frame.contains(locationInWindow)
        } else {
            overTimeline = false
        }
        chrome.pointerMoved(overTimeline: overTimeline)
    }

    private func applyTimelineVisibility(_ visible: Bool) {
        guard let timelineHost else { return }
        visibilityGeneration &+= 1
        let generation = visibilityGeneration
        let close = closeButton

        if visible {
            timelineHost.isHidden = false
            close?.isHidden = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                timelineHost.animator().alphaValue = 1
                close?.animator().alphaValue = 1
            }
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            timelineHost.animator().alphaValue = 0
            close?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                // Ignore stale hide completions after a newer reveal.
                guard self.visibilityGeneration == generation else { return }
                guard !self.chrome.isVisible else { return }
                self.timelineHost?.isHidden = true
                self.closeButton?.isHidden = true
            }
        })
    }

    private func makeCloseButton() -> NSButton {
        let b = NSButton()
        b.bezelStyle = .accessoryBarAction
        b.image = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left",
                          accessibilityDescription: "Exit Full Screen")
        b.imagePosition = .imageOnly
        b.isBordered = false
        b.target = self
        b.action = #selector(closeButtonTapped)
        b.toolTip = "Exit Full Screen (⌃⌘F or Esc)"
        b.contentTintColor = .labelColor
        return b
    }

    @objc private func closeButtonTapped() {
        closeWindow()
    }

    func closeWindow() {
        guard window != nil else {
            finishEndedIfNeeded()
            return
        }
        window?.close()
    }

    private func finishEndedIfNeeded() {
        guard !didEnd else { return }
        didEnd = true
        if didApplyPresentationOptions {
            NSApplication.shared.presentationOptions = savedPresentationOptions
            didApplyPresentationOptions = false
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        chrome.cancel()
        playerView.player = nil
        subtitleHost?.removeFromSuperview()
        subtitleHost = nil
        timelineHost?.removeFromSuperview()
        timelineHost = nil
        closeButton = nil
        window?.delegate = nil
        window = nil
        onEnded?()
        onEnded = nil
    }

    func windowWillClose(_ notification: Notification) {
        finishEndedIfNeeded()
    }
}

/// Forwards hits on empty areas to views below (full-screen subtitle host).
private final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}
