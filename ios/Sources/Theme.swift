import SwiftUI

/// Recall's palette: deep ink, off-white type, one periwinkle accent.
/// Confident venture-tool look — dark, high contrast, minimal chrome.
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Page background.
    static let rcInk = Color(hex: 0x0E1116)
    /// Raised card.
    static let rcSurface = Color(hex: 0x161B22)
    /// Field / chip fill on top of a card.
    static let rcSurfaceHi = Color(hex: 0x1E252F)
    /// Hairline borders.
    static let rcLine = Color(hex: 0x272F3A)
    /// Primary text.
    static let rcText = Color(hex: 0xF3F6F8)
    /// Secondary text.
    static let rcTextDim = Color(hex: 0x8D98A8)
    /// The one accent — brand periwinkle, from the app-icon dot.
    static let rcAccent = Color(hex: 0x7B68EE)
    /// Accent, pushed back for fills.
    static let rcAccentSoft = Color(hex: 0x3B3480)
    /// Destructive / privacy actions.
    static let rcAlert = Color(hex: 0xF87171)
}

extension Font {
    /// Display face for headings — heavy system sans, tightened.
    static func rcDisplay(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static let rcBody = Font.system(size: 16)
    static let rcBodyMedium = Font.system(size: 16, weight: .medium)
    static let rcCaption = Font.system(size: 13.5)
    /// All-caps section labels.
    static let rcLabel = Font.system(size: 11.5, weight: .bold)
    static let rcMono = Font.system(size: 14, design: .monospaced)
}

// MARK: - Wordmark

/// The Recall wordmark, in live text: `rec` ghosted + `all` full weight.
///
/// Brand spec asks for Poppins Medium/SemiBold; no TTF ships with the app, so
/// this falls back to the system sans at the same weights with the same
/// two-tone treatment. Ghost opacity follows the variant table in BRAND.md —
/// 0.30 for the reversed variant used across this dark UI.
struct Wordmark: View {
    var size: CGFloat = 22
    /// Ghost opacity for `rec`: 0.30 reversed (dark UI), 0.45 hardware, 0.20 primary.
    var ghost: Double = 0.30
    var color: Color = .rcText

    var body: some View {
        (
            Text("rec")
                .font(.system(size: size, weight: .medium))
                .foregroundColor(color.opacity(ghost))
                + Text("all")
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(color)
        )
        .tracking(-0.5)
        .accessibilityLabel("Recall")
    }
}

/// Wordmark plus the accent dot from the app icon — used in nav titles.
struct WordmarkLockup: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: 5) {
            Wordmark(size: size)
            Circle()
                .fill(Color.rcAccent)
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(y: -size * 0.28)
        }
    }
}

// MARK: - Surfaces & controls

struct PanelCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rcSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.rcLine, lineWidth: 1)
            )
    }
}

extension View {
    func panel() -> some View { modifier(PanelCard()) }

    /// Standard Recall screen chrome: ink background, dark bars.
    func recallScreen() -> some View {
        self
            .background(Color.rcInk.ignoresSafeArea())
            .toolbarBackground(Color.rcInk, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// Small all-caps label used above sections and fields.
struct SectionLabel: View {
    let text: String
    var icon: String?

    init(_ text: String, icon: String? = nil) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(text.uppercased())
                .font(.rcLabel)
                .tracking(1.4)
        }
        .foregroundStyle(Color.rcAccent)
    }
}

/// Pill chip for topics, follow-ups and badges.
struct Chip: View {
    let text: String
    var tint: Color = .rcAccent
    var filled = false

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(filled ? Color.rcInk : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(filled ? tint : tint.opacity(0.14))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(tint.opacity(filled ? 0 : 0.35), lineWidth: 1)
            )
    }
}

/// Full-width accent button used for primary actions.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.rcAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Bordered secondary button.
struct GhostButtonStyle: ButtonStyle {
    var tint: Color = .rcText

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.rcSurfaceHi)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.rcLine, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
