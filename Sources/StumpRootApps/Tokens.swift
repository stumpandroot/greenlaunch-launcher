import AppKit
import SwiftUI

// The Verbose family look (Verbose's mac/DESIGN.md §13, Views/Tokens.swift). The system draws the chrome: the
// sidebar, the toolbar, menus, alerts, and Settings. These values draw the content: the paper page, off-white cards
// with no outlines, serif titles, and the palette fills. Every value has a light and a dark value.

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

enum Refined {
    /// A color with a light and a dark value.
    static func tone(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.isDark ? dark : light)
        })
    }

    /// A color laid over whatever is under it, at one opacity in light and another in dark.
    static func wash(_ light: UInt32, _ dark: UInt32, _ lightAlpha: CGFloat, _ darkAlpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        })
    }

    // Surfaces
    static let paper = tone(0xF5F0E6, 0x18241F)
    static let card = tone(0xFFFDF9, 0x202F28)
    static let rail = tone(0xE0D9CB, 0x33433B)
    static let neutralSquare = tone(0xE6DFD1, 0x2E3B34)

    // Text
    static let ink = tone(0x26352E, 0xF5F0E6)
    static let dim = tone(0x545E56, 0xD4CDC0)
    static let mute = tone(0x606962, 0xA1A29A)
    static let faint = tone(0x8E938A, 0x6F7A72)
    static let accentText = tone(0xB23F24, 0xFF8A6B)
    static let sageText = tone(0x4F6440, 0xB9CDA3)
    static let danger = tone(0xB3261E, 0xFF8A80)
    /// Ink on a palette fill, in both modes: the fills stay light in dark mode, so their text stays ink.
    static let onFill = Color(hex: 0x26352E)

    // Fills
    static let persimmon = tone(0xFB7350, 0xF27A57)
    static let butter = tone(0xF4C76B, 0xDDB563)
    static let sage = tone(0xAFC398, 0x9DB088)
    static let petal = tone(0xEFB6C8, 0xD9A3B5)
    static let persimmonTint = tone(0xFDE4DA, 0x3A2A22)

    // Washes
    static let separator = wash(0x26352E, 0xF5F0E6, 0.10, 0.12)
    static let neutral = wash(0x26352E, 0xF5F0E6, 0.07, 0.08)
    static let hoverWash = wash(0x26352E, 0xF5F0E6, 0.04, 0.05)

    static func fill(_ hue: Hue) -> Color {
        switch hue {
        case .persimmon: return persimmon
        case .butter: return butter
        case .sage: return sage
        case .petal: return petal
        case .neutral: return neutralSquare
        }
    }

    /// The text color that reads on `fill(hue)`.
    static func inkOn(_ hue: Hue) -> Color { hue == .neutral ? ink : onFill }

    /// New York, for titles.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    // Radii on the Mac: cards 12, tiles 14, small controls 8.
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
}

/// A button on the page. Strong is ink with light text, for a card's main action; quiet is the neutral wash with ink
/// text. A press dims the button; it doesn't scale.
struct RefinedActionStyle: ButtonStyle {
    enum Kind { case strong, quiet }
    var kind: Kind = .strong

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(height: 28)
            .foregroundStyle(kind == .strong ? Refined.paper : Refined.ink)
            .background(
                RoundedRectangle(cornerRadius: Refined.controlRadius, style: .continuous)
                    .fill(kind == .strong ? Refined.ink : Refined.neutral)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Refined.controlRadius, style: .continuous))
    }
}

/// A small capsule label, like "Update to v1.2.1": the persimmon tint with accent text.
struct RefinedChipLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Refined.accentText)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Refined.persimmonTint))
    }
}

/// A screen's title: one line in the meta style over the large serif title.
struct LargeSerifTitle: View {
    let title: String
    let eyebrow: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Refined.mute)
            Text(title)
                .font(Refined.serif(32))
                .foregroundStyle(Refined.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A group's label over its cards.
struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(Refined.serif(20))
            .foregroundStyle(Refined.ink)
            .accessibilityAddTraits(.isHeader)
    }
}
