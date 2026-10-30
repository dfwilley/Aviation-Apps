import SwiftUI
import UIKit

// Colors and type matching the web app, with its dark-mode palette.

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: 1)
    }

    static func pair(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }
}

enum Palette {
    static let bg = UIColor.pair(0xf3f5f7, 0x11161c)
    static let panel = UIColor.pair(0xffffff, 0x18202a)
    static let ink = UIColor.pair(0x18212b, 0xe4eaf0)
    static let muted = UIColor.pair(0x5a6773, 0x9aa8b5)
    static let rule = UIColor.pair(0xd6dde3, 0x2c3946)
    static let accent = UIColor.pair(0x1f5f8b, 0x7fb6dc)
    static let accentSoft = UIColor.pair(0xe2edf5, 0x1d3142)
    static let ok = UIColor.pair(0x2e7d4f, 0x6fcf97)
    static let okSoft = UIColor.pair(0xe1f2e8, 0x173326)
    static let bad = UIColor.pair(0xb3261e, 0xff8a80)
    static let badSoft = UIColor.pair(0xfbe4e2, 0x3a1c1a)
    static let warn = UIColor.pair(0xa15c00, 0xf0b35a)
    static let warnSoft = UIColor.pair(0xfbefdc, 0x3a2a12)
    static let env = UIColor.pair(0x1f5f8b, 0x7fb6dc)
    static let env2 = UIColor.pair(0x8a6bb8, 0xb9a0e0)
    static let point = UIColor.pair(0x18212b, 0xe4eaf0)
}

enum Theme {
    static let bg = Color(Palette.bg)
    static let panel = Color(Palette.panel)
    static let ink = Color(Palette.ink)
    static let muted = Color(Palette.muted)
    static let rule = Color(Palette.rule)
    static let accent = Color(Palette.accent)
    static let accentSoft = Color(Palette.accentSoft)
    static let ok = Color(Palette.ok)
    static let okSoft = Color(Palette.okSoft)
    static let bad = Color(Palette.bad)
    static let badSoft = Color(Palette.badSoft)
    static let warn = Color(Palette.warn)
    static let warnSoft = Color(Palette.warnSoft)

    /// A palette color fixed for the current light/dark setting (used inside the chart drawing).
    static func fixed(_ c: UIColor, _ scheme: ColorScheme) -> Color {
        Color(c.resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)))
    }

    /// Condensed headings (stands in for Barlow Semi Condensed).
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Numbers (stands in for JetBrains Mono).
    static func data(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func body(_ size: CGFloat = 16, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// White card with a thin border, like the web app's panels.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct PanelTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(Theme.display(20, .semibold)).foregroundColor(Theme.ink)
    }
}
