import Foundation

/// Semantic design tokens.
///
/// Grouped by role — `BackgroundTokens`, `TextTokens`, `UnderlineTokens`,
/// `FillTokens`, `Space`, `Radius`, `ControlState` — rather than by value, so
/// a view asks for "the correctness underline" and never for a hex string.
/// Changing the palette is then one edit here, not a search across the views.
public enum Theme {

    /// An RGB colour with an ANSI-256 approximation for terminal rendering.
    public struct Color: Equatable, Sendable {
        public let hex: String
        public let ansi: Int
        public init(hex: String, ansi: Int) { self.hex = hex; self.ansi = ansi }

        public func fg(_ s: String) -> String { "\u{1B}[38;5;\(ansi)m\(s)\u{1B}[0m" }
        public func underline(_ s: String) -> String {
            "\u{1B}[4m\u{1B}[38;5;\(ansi)m\(s)\u{1B}[0m"
        }
    }

    /// Corrector's palette — teal / amber / violet / rose / slate, chosen for
    /// AA contrast on both light and dark terminals.
    public enum Palette {
        public static let teal   = Color(hex: "#0E8C7F", ansi: 36)
        public static let amber  = Color(hex: "#C47F17", ansi: 178)
        public static let violet = Color(hex: "#6A54C9", ansi: 99)
        public static let rose   = Color(hex: "#C0405E", ansi: 168)
        public static let slate  = Color(hex: "#5A6572", ansi: 245)
        public static let indigo = Color(hex: "#3D64B8", ansi: 68)
        public static let muted  = Color(hex: "#8A94A0", ansi: 244)
    }

    /// Underlines carry an active and an inactive variant: the selected
    /// suggestion has to stand out from the rest without changing colour.
    public enum UnderlineTokens {
        public static func color(for outcome: CardLayout.Outcome,
                                 active: Bool) -> Color {
            let base = FillTokens.color(for: outcome)
            return active ? base : Palette.muted
        }
    }

    public enum FillTokens {
        public static func color(for outcome: CardLayout.Outcome) -> Color {
            switch outcome {
            case.correctness: return Palette.rose
            case.clarity:     return Palette.teal
            case.engagement:  return Palette.violet
            case.delivery:    return Palette.indigo
            case.styleGuide:  return Palette.amber
            case.inclusivity: return Palette.teal
            }
        }
    }

    public enum TextTokens {
        public static let primary = Color(hex: "#15202B", ansi: 252)
        public static let secondary = Palette.slate
        public static let onAccent = Color(hex: "#FFFFFF", ansi: 231)
    }

    /// 4-point spacing scale.
    public enum Space {
        public static let xs = 2, sm = 4, md = 8, lg = 12, xl = 16
    }

    public enum Radius {
        public static let sm = 4, md = 8, lg = 12
    }

    /// Control states, so hover and disabled styling is named here rather than
    /// improvised per view.
    public enum ControlState: String, Sendable {
        case normal, hover, active, disabled
    }
}
