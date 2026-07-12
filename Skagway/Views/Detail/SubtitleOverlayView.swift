import SwiftUI

/// Netflix-style subtitle overlay: semi-bold white sans-serif text with a strong soft shadow
/// (no outline, no background box), anchored near the bottom of the video with a resolution-aware
/// bottom inset and font size. Cross-fades between cues.
struct SubtitleOverlayView: View {
    /// Current visible text, or `nil`/empty to show nothing.
    let text: String?

    /// Bottom inset as a fraction of overlay height. 7% lands above letterbox safe area.
    var bottomInsetFraction: CGFloat = 0.07
    /// Font size as a fraction of overlay height. 3.75% reads comfortably from a couch at
    /// typical laptop/monitor distances without dominating the frame.
    var fontSizeFraction: CGFloat = 0.0375
    /// Clamp font size so very small preview players stay readable and 4K+ sizes don't explode.
    var minFontSize: CGFloat = 14
    var maxFontSize: CGFloat = 48
    /// Cross-fade duration between cues.
    var fadeDuration: Double = 0.15

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let fontSize = min(max(h * fontSizeFraction, minFontSize), maxFontSize)
            let bottomPadding = h * bottomInsetFraction
            let horizontalPadding = max(16, geo.size.width * 0.05)

            ZStack(alignment: .bottom) {
                Color.clear
                if let t = text, !t.isEmpty {
                    subtitleText(t, fontSize: fontSize)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.bottom, bottomPadding)
                        .frame(maxWidth: .infinity, alignment: .center)
                        // `.id(t)` forces SwiftUI to treat each distinct cue as a new view,
                        // which enables the fade-out-then-fade-in crossfade via the parent animation.
                        .id(t)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            .animation(.easeInOut(duration: fadeDuration), value: text ?? "")
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    /// The styled text itself. Two stacked shadows (tight + wide) give the "floating" look —
    /// the tight one provides contrast on bright scenes; the wide one anchors the text so it
    /// doesn't feel like it's just stamped on top.
    @ViewBuilder
    private func subtitleText(_ t: String, fontSize: CGFloat) -> some View {
        Text(t)
            .font(.system(size: fontSize, weight: .semibold, design: .default))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(0.95), radius: 3, x: 0, y: 1)
            .shadow(color: .black.opacity(0.75), radius: 6, x: 0, y: 2)
    }
}

/// Small connector that re-renders the overlay when the observed `SubtitleTrack` changes.
/// Put this inside your player's ZStack (inline) or wrap it in an `NSHostingView` (fullscreen).
struct SubtitleOverlayContainer: View {
    let track: SubtitleTrack

    var body: some View {
        SubtitleOverlayView(text: track.isEnabled ? track.currentCue?.text : nil)
    }
}
