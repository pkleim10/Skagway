import SwiftUI

/// Stylized macOS traffic-light cluster for the floating / fullscreen play chrome.
/// Not real `NSWindow` buttons (those surfaces are custom), but sized and colored to match
/// the system close / miniaturize / zoom controls.
struct PlayerTrafficLights: View {
    /// Compact-mode yellow/green mapping. Flip this to restore Option A without rewriting call sites.
    enum CompactMapping {
        /// Option A: Yellow no-op (dimmed), Green → Windowed.
        case optionA_yellowNopGreenWindowed
        /// Option B: Compact ladder — Yellow → Windowed, Green → Full screen.
        case optionB_compactLadder
    }

    /// Active compact mapping. Change to `.optionA_yellowNopGreenWindowed` to revert.
    static let compactMapping: CompactMapping = .optionB_compactLadder

    enum Mode {
        /// Yellow → Compact, Green → Full screen.
        case windowed
        /// Compact mapping — see `compactMapping`.
        case compact
        /// Yellow → Compact, Green → Windowed.
        case fullScreen
    }

    var mode: Mode
    var onClose: () -> Void
    var onYellow: () -> Void
    var onGreen: () -> Void

    @State private var isClusterHovered = false

    /// System traffic-light diameter.
    private static let diameter: CGFloat = 12
    /// Gap between circles (centers are 20pt apart).
    private static let spacing: CGFloat = 8

    private static let closeColor = Color(red: 255 / 255, green: 95 / 255, blue: 87 / 255)
    private static let miniaturizeColor = Color(red: 254 / 255, green: 188 / 255, blue: 46 / 255)
    private static let zoomColor = Color(red: 40 / 255, green: 200 / 255, blue: 64 / 255)

    private var yellowEnabled: Bool {
        switch mode {
        case .compact:
            return Self.compactMapping != .optionA_yellowNopGreenWindowed
        case .windowed, .fullScreen:
            return true
        }
    }

    private var yellowHelp: String {
        switch mode {
        case .compact:
            switch Self.compactMapping {
            case .optionA_yellowNopGreenWindowed: return "Compact"
            case .optionB_compactLadder: return "Windowed (⌃⌘W)"
            }
        case .windowed, .fullScreen:
            return "Compact (⌃⌘C)"
        }
    }

    private var yellowSymbol: String {
        switch mode {
        case .compact where Self.compactMapping == .optionB_compactLadder:
            return "macwindow"
        default:
            return "minus"
        }
    }

    private var greenHelp: String {
        switch mode {
        case .compact:
            switch Self.compactMapping {
            case .optionA_yellowNopGreenWindowed: return "Windowed (⌃⌘W)"
            case .optionB_compactLadder: return "Full screen (⌃⌘F)"
            }
        case .windowed: return "Full screen (⌃⌘F)"
        case .fullScreen: return "Windowed (⌃⌘F)"
        }
    }

    private var greenSymbol: String {
        switch mode {
        case .fullScreen:
            return "arrow.down.right.and.arrow.up.left"
        case .windowed, .compact:
            return "arrow.up.left.and.arrow.down.right"
        }
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            light(
                fill: Self.closeColor,
                help: "Stop playback (Esc)",
                symbol: "xmark",
                symbolOffset: .zero,
                enabled: true,
                action: onClose
            )
            light(
                fill: Self.miniaturizeColor,
                help: yellowHelp,
                symbol: yellowSymbol,
                // `macwindow` glyph is optically left-heavy in a 12pt circle (half-pt nudge).
                symbolOffset: yellowSymbol == "macwindow" ? CGSize(width: 0.25, height: 0) : .zero,
                enabled: yellowEnabled,
                action: onYellow
            )
            light(
                fill: Self.zoomColor,
                help: greenHelp,
                symbol: greenSymbol,
                symbolOffset: .zero,
                enabled: true,
                action: onGreen
            )
        }
        .onHover { isClusterHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Player window controls")
    }

    private func light(
        fill: Color,
        help: String,
        symbol: String,
        symbolOffset: CGSize,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fill.opacity(enabled ? 1 : 0.35))
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(enabled ? 0.12 : 0.06), lineWidth: 0.5)
                    )
                if isClusterHovered, enabled {
                    Image(systemName: symbol)
                        .font(.system(size: symbol == "macwindow" ? 7 : 6.5, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .offset(x: symbolOffset.width, y: symbolOffset.height)
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(enabled ? [] : .isStaticText)
    }

    /// Leading padding from the panel’s left edge to the red light (title-bar inset).
    static let leadingInset: CGFloat = 12
    /// Space between the green light and the title text.
    static let titleGap: CGFloat = 14
    /// Width of the three lights including inter-light gaps.
    static var clusterWidth: CGFloat { diameter * 3 + spacing * 2 }
    /// Total leading chrome reserved for lights + gaps (spacer / drag inset).
    static var leadingChromeWidth: CGFloat {
        leadingInset + clusterWidth + titleGap
    }
}
