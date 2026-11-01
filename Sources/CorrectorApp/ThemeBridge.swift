import SwiftUI
import AppKit
import CorrectorCore
import CorrectorAppCore

/// Bridges Corrector's semantic tokens to AppKit and SwiftUI.
///
/// `CorrectorCore.Theme` deliberately knows nothing about AppKit so the model
/// layer stays testable off-screen; the conversion lives here, in the only
/// target that draws.
extension Theme.Color {
    var nsColor: NSColor {
        var hex = self.hex
        if hex.hasPrefix("#") { hex.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
                       green: CGFloat((value >> 8) & 0xFF) / 255.0,
                       blue: CGFloat(value & 0xFF) / 255.0,
                       alpha: 1.0)
    }

    var swiftUIColor: Color { Color(nsColor) }
}

extension CardLayout.Outcome {
    var tint: Color { Theme.FillTokens.color(for: self).swiftUIColor }
    var tintNS: NSColor { Theme.FillTokens.color(for: self).nsColor }

    /// Underlines carry an active and an inactive variant, so the selected
    /// suggestion stands out without changing colour.
    func underlineNS(active: Bool) -> NSColor {
        Theme.UnderlineTokens.color(for: self, active: active).nsColor
    }

    /// An SF Symbol per category, so the app ships no image assets and the
    /// icons follow the system's weight and accent.
    var symbolName: String {
        switch self {
        case.correctness: return "exclamationmark.circle.fill"
        case.clarity:     return "wand.and.stars"
        case.engagement:  return "bolt.fill"
        case.delivery:    return "paperplane.fill"
        case.styleGuide:  return "text.badge.checkmark"
        case.inclusivity: return "person.2.fill"
        }
    }
}

/// Spacing and radius, read from the token scale rather than hard-coded, so the
/// scale stays a single source of truth.
enum Metric {
    static let xs = CGFloat(Theme.Space.xs)
    static let sm = CGFloat(Theme.Space.sm)
    static let md = CGFloat(Theme.Space.md)
    static let lg = CGFloat(Theme.Space.lg)
    static let xl = CGFloat(Theme.Space.xl)

    static let radiusSmall = CGFloat(Theme.Radius.sm)
    static let radiusMedium = CGFloat(Theme.Radius.md)
    static let radiusLarge = CGFloat(Theme.Radius.lg)
}
