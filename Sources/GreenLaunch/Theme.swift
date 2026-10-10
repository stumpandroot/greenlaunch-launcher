import SwiftUI

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
}

/// GreenLaunch brand colors.
enum Brand {
    static let ink = Color(hex: 0x002B00)
    static let lime = Color(hex: 0xB4E43A)
    static let cream = Color(hex: 0xFAFEE2)
    static let line = Color(hex: 0xD3DDAA)
    static let muted = Color(hex: 0x44593D)
    static let orange = Color(hex: 0xFF7F11)
    static let error = Color(hex: 0x8A2A0A)
}

/// Solid dark green button for the main action in a row.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 28)
            .foregroundStyle(Brand.cream)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Brand.ink.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// Outlined button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundStyle(Brand.ink)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Brand.ink.opacity(configuration.isPressed ? 0.08 : 0))
            )
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.ink, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// Small rounded label, like "Update to v1.2.1".
struct Pill: View {
    let text: String
    var fill: Color = Brand.lime
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(fill))
    }
}
