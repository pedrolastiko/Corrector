import Foundation
import AppKit
import CorrectorCore

/// A misspelling found in a document.
public struct Misspelling: Equatable, Sendable {
    /// UTF-16 offsets, matching the suggestion schema.
    public let begin: Int
    public let end: Int
    public let word: String
    /// Replacements, best first. May be empty when nothing plausible is known.
    public let suggestions: [String]
}

/// Where spelling knowledge comes from.
///
/// This exists so the engine can be deterministic in tests and knowledgeable in
/// production. A curated table gives repeatable results a test can assert on,
/// but only knows the words someone typed into it; the system dictionary knows
/// the language but can change between macOS releases.
public protocol SpellDictionary: Sendable {
    /// `dialect` is passed alongside `language` rather than derived from it:
    /// "colour" is correct British English and a misspelling in American
    /// English, so a dictionary that only knows the language cannot answer.
    func misspellings(in text: String, tokens: [Token],
                      language: Language, dialect: Dialect) -> [Misspelling]
}

// MARK: - Curated table

/// A fixed table of known misspellings and their corrections.
///
/// Deterministic by construction, which is what the test suite needs. It is
/// also genuinely better than the system dictionary for the handful of errors
/// it covers: it knows that `alot` is two words and that `teh` is `the`, where
/// a general dictionary may rank other candidates first.
public struct TableSpellDictionary: SpellDictionary {
    let corrections: [Language: [String: String]]

    public init(corrections: [Language: [String: String]]) {
        self.corrections = corrections
    }

    public static let standard = TableSpellDictionary(corrections: [
        .english: SpellingPlugin.corrections,
        .french: FrenchSpellingPlugin.corrections,
    ])

    /// The table is dialect-blind: every entry in it is wrong in every
    /// variant of the language, which is the point of a curated list.
    public func misspellings(in text: String, tokens: [Token],
                             language: Language, dialect: Dialect) -> [Misspelling] {
        let table = corrections[language] ?? [:]
        return tokens.compactMap { token in
            guard let fix = table[token.lower], fix != token.lower else { return nil }
            return Misspelling(begin: token.begin, end: token.end, word: token.text,
                               suggestions: [matchCase(fix, like: token.text)])
        }
    }

    func matchCase(_ replacement: String, like original: String) -> String {
        if original.count > 1, original.allSatisfy({ !$0.isLetter || $0.isUppercase }) {
            return replacement.uppercased()
        }
        if let first = original.first, first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}

// MARK: - System dictionary

/// The dictionaries macOS already ships, through `NSSpellChecker`.
///
/// This is what turns Corrector from a lookup table of a couple of hundred
/// entries into something that actually knows English and French. It costs
/// determinism — Apple may change its dictionaries — which is why tests use
/// the table instead.
///
/// Marked `@unchecked Sendable`: `NSSpellChecker` is not thread-safe, and this
/// type must only be used from the main thread. Both front ends do.
public final class SystemSpellDictionary: SpellDictionary, @unchecked Sendable {
    private let tag: Int

    public init() {
        tag = NSSpellChecker.uniqueSpellDocumentTag()
    }

    /// The system's language code for a dialect. There is no `en_US` on macOS;
    /// plain `en` is the American dictionary.
    public static func code(for dialect: Dialect) -> String {
        switch dialect {
        case .american: return "en"
        case .british: return "en_GB"
        case .canadian: return "en_CA"
        case .australian: return "en_AU"
        case .indian: return "en_IN"
        case .french: return "fr"
        case .canadianFrench: return "fr_CA"
        case .belgianFrench: return "fr_BE"
        case .swissFrench: return "fr_CH"
        case .auto: return "en"
        }
    }

    /// The best code macOS can actually serve for this dialect.
    ///
    /// Asking `NSSpellChecker` for `en_CA` on a machine where only `en` is
    /// installed returns nothing at all — not "no mistakes", but no checking.
    /// Falling back to the base language keeps a Canadian user spell-checked
    /// in generic English rather than silently unchecked, which is how the
    /// first version of this would have failed the moment it started passing
    /// a regional code.
    static func resolvedCode(for dialect: Dialect, language: Language,
                             available: [String]) -> String? {
        let preferred = code(for: dialect)
        if available.contains(preferred) { return preferred }
        let base = language.code                   // "en" / "fr"
        return available.contains(base) ? base : nil
    }

    public func misspellings(in text: String, tokens: [Token],
                             language: Language, dialect: Dialect) -> [Misspelling] {
        let checker = NSSpellChecker.shared
        guard let code = Self.resolvedCode(for: dialect, language: language,
                                           available: checker.availableLanguages)
        else { return [] }

        let ns = text as NSString
        var found: [Misspelling] = []
        var cursor = 0

        while cursor < ns.length {
            let range = checker.checkSpelling(of: text, startingAt: cursor,
                                              language: code, wrap: false,
                                              inSpellDocumentWithTag: tag,
                                              wordCount: nil)
            guard range.location != NSNotFound, range.length > 0 else { break }
            cursor = NSMaxRange(range)

            let word = ns.substring(with: range)
            guard Self.isWorthFlagging(word), !checker.hasLearnedWord(word) else { continue }

            let guesses = (checker.guesses(forWordRange: range, in: text,
                                           language: code,
                                           inSpellDocumentWithTag: tag) ?? [])
                .filter { Self.isUsefulSuggestion($0, for: word) }
            found.append(Misspelling(begin: range.location, end: NSMaxRange(range),
                                     word: word, suggestions: Array(guesses.prefix(4))))
        }
        return found
    }

    /// Reject a suggestion that differs from the word only in capitalisation.
    ///
    /// A dictionary asked about a loanword it does not know — "manpower" in a
    /// French sentence — often answers with the same letters capitalised. That
    /// is not a correction; applying it changes nothing a writer wanted. The
    /// word is still reported as unknown, just without a bogus fix attached.
    static func isUsefulSuggestion(_ suggestion: String, for word: String) -> Bool {
        suggestion.lowercased() != word.lowercased()
    }

    /// Filter out the things a dictionary flags but a writer does not want
    /// underlined: single letters, anything containing a digit, and acronyms.
    static func isWorthFlagging(_ word: String) -> Bool {
        guard word.count > 1 else { return false }
        if word.contains(where: \.isNumber) { return false }
        if word.count <= 5, word.allSatisfy({ !$0.isLetter || $0.isUppercase }) { return false }
        return true
    }
}

// MARK: - Composite

/// Curated table first, system dictionary for everything else.
///
/// The order matters: where the table has an opinion it is the better one,
/// because it was written for that specific confusion. The system dictionary
/// then covers the vastly larger set of words nobody listed by hand.
public struct CompositeSpellDictionary: SpellDictionary {
    let primary: SpellDictionary
    let fallback: SpellDictionary

    public init(primary: SpellDictionary, fallback: SpellDictionary) {
        self.primary = primary
        self.fallback = fallback
    }

    public func misspellings(in text: String, tokens: [Token],
                             language: Language, dialect: Dialect) -> [Misspelling] {
        let fromTable = primary.misspellings(in: text, tokens: tokens,
                                             language: language, dialect: dialect)
        let covered = fromTable.map { $0.begin }
        let rest = fallback.misspellings(in: text, tokens: tokens,
                                         language: language, dialect: dialect)
            .filter { !covered.contains($0.begin) }
        return (fromTable + rest).sorted { $0.begin < $1.begin }
    }
}
