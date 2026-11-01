import Foundation

/// How a suggestion is presented: which category it belongs to and how its
/// card and underline are styled.
///
/// Three fields rather than one, because the three questions are independent:
/// which category a suggestion belongs to, how it is presented, and what
/// muting it would silence. Two rules can share a colour and still mute apart.
public struct CardLayout: Equatable, Hashable, Codable, Sendable {
    public var outcome: Outcome
    public var group: Group
    public var userMuteCategory: String?

    public init(outcome: Outcome, group: Group = .suggestion, userMuteCategory: String? = nil) {
        self.outcome = outcome
        self.group = group
        self.userMuteCategory = userMuteCategory
    }

    /// The top-level suggestion categories.
    ///
    /// Six categories rather than one flat rule list: the sidebar groups by
    /// these, and the priority below decides which underline wins when two
    /// rules cover the same span. The titles, priorities and colours here are
    /// the single source for both the terminal and the app.
    public enum Outcome: String, CaseIterable, Codable, Sendable {
        case correctness
        case clarity
        case engagement
        case delivery
        case styleGuide
        case inclusivity

        /// Display name shown on the card header.
        public var title: String {
            switch self {
            case.correctness: return "Correctness"
            case.clarity:     return "Clarity"
            case.engagement:  return "Engagement"
            case.delivery:    return "Delivery"
            case.styleGuide:  return "Style guide"
            case.inclusivity: return "Inclusivity"
            }
        }

        /// Sort order for the card list — lower sorts first.
        ///
        /// Mirrors `CardLayout.Outcome.priority: Int`.
        /// Correctness first because those are objective errors.
        public var priority: Int {
            switch self {
            case.correctness: return 0
            case.clarity:     return 1
            case.engagement:  return 2
            case.delivery:    return 3
            case.styleGuide:  return 4
            case.inclusivity: return 5
            }
        }

        /// A single ASCII glyph per category, for the terminal renderer, where
        /// an SF Symbol has nothing to draw with.
        public var glyph: String {
            switch self {
            case.correctness: return "!"
            case.clarity:     return "~"
            case.engagement:  return "+"
            case.delivery:    return ">"
            case.styleGuide:  return "="
            case.inclusivity: return "*"
            }
        }
    }

    /// Card grouping: a full card, an inline suggestion shown without one, or
    /// an informational banner that has nothing to accept.
    public enum Group: String, Codable, Sendable {
        case suggestion
        case inline
        case informational
    }
}
