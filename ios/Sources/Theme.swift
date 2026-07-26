import SwiftUI

// Warm cream / amber / terracotta palette shared with the web dashboard.
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

    static let rsCream = Color(hex: 0xFAF6EF)
    static let rsCard = Color(hex: 0xFFFCF6)
    static let rsTerracotta = Color(hex: 0xC05B3C)
    static let rsAmber = Color(hex: 0xE3A252)
    static let rsInk = Color(hex: 0x3B2E24)
    static let rsInkSoft = Color(hex: 0x7A6B5C)
    static let rsSage = Color(hex: 0x7C8B6A)
    static let rsWarn = Color(hex: 0xA6402A)
}

extension Font {
    /// Serif display face for the keepsake feel.
    static func rsSerif(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let rsBody = Font.system(size: 18)
    static let rsBodyMedium = Font.system(size: 18, weight: .medium)
    static let rsCaption = Font.system(size: 15)
}

struct SoftCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rsCard)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.rsInk.opacity(0.06), radius: 10, y: 4)
    }
}

extension View {
    func softCard() -> some View { modifier(SoftCard()) }
}

/// Whisper kind → accent color.
func rsKindColor(_ kind: String) -> Color {
    switch kind {
    case "recognition": return .rsTerracotta
    case "warning": return .rsWarn
    case "reassurance": return .rsSage
    default: return .rsInkSoft
    }
}

func rsKindIcon(_ kind: String) -> String {
    switch kind {
    case "recognition": return "person.crop.circle.badge.checkmark"
    case "warning": return "hand.raised.fill"
    case "reassurance": return "heart.fill"
    default: return "sparkles"
    }
}
