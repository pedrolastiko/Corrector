import Foundation
import CorrectorCore

/// Feature flags that enable or disable individual checks.
///
/// One flag per check, negotiated once at session start rather than consulted
/// at every call site. A transient field gets correctness only; the window gets
/// whatever the user left enabled. The engine then runs what it was granted and
/// no view has to ask whether a category is on.
public struct FeatureSet: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let spelling      = FeatureSet(rawValue: 1 << 0)
    public static let grammar       = FeatureSet(rawValue: 1 << 1)
    public static let punctuation   = FeatureSet(rawValue: 1 << 2)
    public static let clarity       = FeatureSet(rawValue: 1 << 3)
    public static let engagement    = FeatureSet(rawValue: 1 << 4)
    public static let styleGuide    = FeatureSet(rawValue: 1 << 5)
    public static let inclusivity   = FeatureSet(rawValue: 1 << 6)

    public static let correctnessOnly: FeatureSet = [.spelling, .grammar, .punctuation]
    public static let all: FeatureSet = [.spelling, .grammar, .punctuation,
        .clarity, .engagement, .styleGuide, .inclusivity]
}

/// Everything a plugin is given for one pass over the document.
public struct CheckContext: Sendable {
    public let text: String
    public let revision: Int
    public let tokens: [Token]
    public let sentences: [(begin: Int, end: Int)]
    public let dialect: Dialect
    public let language: Language

    public init(text: String, revision: Int, dialect: Dialect = .american) {
        // `auto` is resolved here, once, so every plugin downstream sees a
        // concrete language.
        let resolved = dialect == .auto
            ? Dialect.default(for: LanguageDetector.detect(in: text))
: dialect
        self.text = text
        self.revision = revision
        self.dialect = resolved
        self.language = resolved.language
        self.tokens = Tokenizer.words(in: text, language: resolved.language)
        self.sentences = Tokenizer.sentences(in: text)
    }

    /// Tokens whose span falls inside `[begin, end)`.
    public func tokens(in range: (begin: Int, end: Int)) -> [Token] {
        tokens.filter { $0.begin >= range.begin && $0.end <= range.end }
    }
}

/// A language variant.
///
/// A dialect, not just a language: "colour" is correct British English and a
/// misspelling in American, so the language alone cannot answer. Each case
/// carries its language above it, which is what makes `french` and
/// `canadianFrench` expressible at all.
public enum Dialect: String, Codable, Sendable, CaseIterable {
    // English
    case american, british, canadian, australian, indian
    // French
    case french, canadianFrench, belgianFrench, swissFrench
    /// Detect from the text itself.
    case auto

    /// The language whose rule set this dialect selects.
    public var language: Language {
        switch self {
        case.american, .british, .canadian, .australian, .indian:
            return .english
        case.french, .canadianFrench, .belgianFrench, .swissFrench:
            return .french
        case.auto:
            return .english            // replaced by detection before use
        }
    }

    public var displayName: String {
        switch self {
        case.american:       return "English (US)"
        case.british:        return "English (UK)"
        case.canadian:       return "English (CA)"
        case.australian:     return "English (AU)"
        case.indian:         return "English (IN)"
        case.french:         return "Français (FR)"
        case.canadianFrench: return "Français (CA)"
        case.belgianFrench:  return "Français (BE)"
        case.swissFrench:    return "Français (CH)"
        case.auto:           return "Detect automatically"
        }
    }

    /// The default dialect for a language.
    public static func `default`(for language: Language) -> Dialect {
        switch language {
        case.english: return .american
        case.french:  return .french
        }
    }
}

/// One independently testable check.
///
/// One rule, one type, one test file. The point of the split is that a rule can
/// be switched off, reasoned about and asserted on without the rest of the
/// engine being involved.
public protocol CheckPlugin: Sendable {
    /// Stable identifier, used in diagnostics.
    var identifier: String { get }
    /// The flag that must be present for this plugin to run.
    var feature: FeatureSet { get }
    /// The languages this plugin understands. The engine skips it for any
    /// other, which is what keeps English rules off French text — the two
    /// disagree outright on, for instance, whether `;` takes a space before it.
    var languages: Set<Language> { get }
    /// Produce suggestions. Offsets must be UTF-16 code units.
    func check(_ context: CheckContext) -> [AlertDraft]
}

public extension CheckPlugin {
    /// Most plugins are written for one language; those that are genuinely
    /// language-agnostic override this.
    var languages: Set<Language> { [.english] }
}

/// A suggestion before the engine assigns it a stable id.
public struct AlertDraft: Sendable {
    public var begin: Int
    public var end: Int
    public var highlightBegin: Int?
    public var highlightEnd: Int?
    public var title: String
    public var details: String
    public var explanation: String
    public var examples: [String]
    public var pname: AlertPname
    public var outcome: CardLayout.Outcome
    public var replacements: [String]
    public var canBeAddedToDictionary: Bool
    public var group: CardLayout.Group

    public init(begin: Int, end: Int,
                highlightBegin: Int? = nil, highlightEnd: Int? = nil,
                title: String, details: String = "", explanation: String = "",
                examples: [String] = [],
                pname: AlertPname, outcome: CardLayout.Outcome,
                replacements: [String] = [],
                canBeAddedToDictionary: Bool = false,
                group: CardLayout.Group = .suggestion) {
        self.begin = begin
        self.end = end
        self.highlightBegin = highlightBegin
        self.highlightEnd = highlightEnd
        self.title = title
        self.details = details
        self.explanation = explanation
        self.examples = examples
        self.pname = pname
        self.outcome = outcome
        self.replacements = replacements
        self.canBeAddedToDictionary = canBeAddedToDictionary
        self.group = group
    }
}
