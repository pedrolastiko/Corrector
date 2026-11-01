import Foundation

/// A natural language the checker can work in.
///
/// One level above `Dialect`, and the split earns its keep: `Language` decides
/// *which rules exist* — French typography rules have no meaning in English —
/// while `Dialect` decides *which variant applies* within them.
public enum Language: String, CaseIterable, Codable, Sendable {
    case english
    case french

    public var displayName: String {
        switch self {
        case.english: return "English"
        case.french:  return "Français"
        }
    }

    /// BCP-47 primary subtag.
    public var code: String {
        switch self {
        case.english: return "en"
        case.french:  return "fr"
        }
    }

    // MARK: - Writing conventions
    //
    // These are the properties the tokenizer and the typography rules branch
    // on, kept here so adding a third language is a matter of describing it
    // rather than editing every call site.

    /// Whether an apostrophe binds the characters on either side into one word.
    ///
    /// English contractions do (`don't`, `it's`). French apostrophes mark
    /// elision, where the apostrophe separates two words (`l'ami` is the
    /// article `l'` plus the noun `ami`), so the tokenizer must split there or
    /// every elided noun would be unrecognisable.
    public var apostropheJoinsWords: Bool {
        switch self {
        case.english: return true
        case.french:  return false
        }
    }

    /// Whether `;` `!` `?` `:` take a space before them.
    ///
    /// This is the most visible typographic difference between the two: French
    /// requires a non-breaking space before double punctuation, English forbids
    /// any space at all. The same input is an error in one language and correct
    /// in the other, which is precisely why the rule set has to be chosen by
    /// language rather than parameterised.
    public var usesSpaceBeforeDoublePunctuation: Bool {
        switch self {
        case.english: return false
        case.french:  return true
        }
    }

    /// The quotation marks this language sets by default.
    public var quotationMarks: (open: String, close: String) {
        switch self {
        case.english: return ("\u{201C}", "\u{201D}")   // “ ”
        case.french:  return ("\u{00AB}", "\u{00BB}")   // « »
        }
    }
}

/// Space characters that matter to French typography.
public enum Typography {
    /// U+00A0 — espace insécable. Used before `:` and inside guillemets.
    public static let noBreakSpace = "\u{00A0}"
    /// U+202F — espace fine insécable. Used before `;` `!` `?`.
    public static let narrowNoBreakSpace = "\u{202F}"
    /// U+2019 — the typographic apostrophe French prefers over U+0027.
    public static let rightSingleQuote = "\u{2019}"

    public static func isNonBreakingSpace(_ character: Character) -> Bool {
        character == "\u{00A0}" || character == "\u{202F}"
    }
}
