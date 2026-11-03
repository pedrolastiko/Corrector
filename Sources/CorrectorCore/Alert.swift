import Foundation
import CorrectorDelta

/// The producer that emitted a suggestion.
///
/// A flat, stable string identifier per rule. Flat rather than nested, and a
/// string rather than an integer, because these names are persisted: a muted
/// rule, a test assertion and a log line all refer to one by name, so renaming
/// or re-parenting a case would silently change what a user muted.
public enum AlertPname: String, Codable, Sendable, CaseIterable {
    case misspelled
    case repeatedWord
    case articleAgreement
    case subjectVerbAgreement
    case lowercaseSentenceStart
    case doubleSpace
    case spaceBeforePunctuation
    case missingTerminalPunctuation
    case wordiness
    case passiveVoice
    case fillerWord
    case weakIntensifier
    case nominalization
    case sentenceLength
    case monotonousOpeners
    case oxfordComma
    case inclusiveLanguage
    // French-specific rules.
    case elision
    case conditionalAfterSi
    case malgreQue
    case pallierA
    case frenchSpacing
    case frenchQuotes
    case spaceAfterApostrophe
    case typographicApostrophe
    case etcEllipsis
}

/// The actions a card offers, computed per alert.
///
/// A bitmask rather than a fixed button row: which actions a card can offer
/// depends on the rule that produced it. A misspelling can be added to the
/// dictionary, a style suggestion cannot, and a rule that explains without
/// proposing a replacement has nothing to accept.
public struct AlertActions: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let accept           = AlertActions(rawValue: 1 << 0)
    public static let dismiss          = AlertActions(rawValue: 1 << 1)
    public static let mute             = AlertActions(rawValue: 1 << 2)
    public static let addToDictionary  = AlertActions(rawValue: 1 << 3)
    public static let moreInfo         = AlertActions(rawValue: 1 << 4)
    public static let feedback         = AlertActions(rawValue: 1 << 5)

    public var labels: [String] {
        var out: [String] = []
        if contains(.accept) { out.append("Accept") }
        if contains(.dismiss) { out.append("Dismiss") }
        if contains(.mute) { out.append("Mute rule") }
        if contains(.addToDictionary) { out.append("Add to dictionary") }
        if contains(.moreInfo) { out.append("Learn more") }
        if contains(.feedback) { out.append("Feedback") }
        return out
    }
}

/// A single suggestion anchored to a span of the document.
///
/// All offsets are **UTF-16 code-unit** offsets, so a span can be handed to
/// `NSTextView` or the Accessibility API without converting anything.
public struct Alert: Equatable, Hashable, Codable, Sendable, Identifiable {
    /// Stable identity. Every re-check produces a fresh alert set; matching the
    /// new one against the old by id is what lets a card update in place
    /// instead of vanishing and reappearing under the pointer.
    public var id: Int

    /// Document revision this alert was computed against.
    public var rev: Int

    /// Replacement range, in UTF-16 code units.
    public var begin: Int
    public var end: Int

    /// Underline range. May be wider than `begin..<end` so the user sees the
    /// context that justifies the suggestion.
    public var highlightBegin: Int
    public var highlightEnd: Int
    public var highlightText: String

    public var title: String
    public var details: String
    public var explanation: String
    public var examples: [String]

    public var category: String
    public var categoryHuman: String
    public var group: String
    public var pname: AlertPname
    public var cardLayout: CardLayout

    /// Candidate replacements, best first.
    public var replacements: [String]

    public var hidden: Bool
    public var muted: Bool
    public var canBeMuted: Bool
    public var hasMoreInfo: Bool
    public var canBeAddedToDictionary: Bool

    public init(
        id: Int, rev: Int,
        begin: Int, end: Int,
        highlightBegin: Int? = nil, highlightEnd: Int? = nil, highlightText: String = "",
        title: String, details: String = "", explanation: String = "", examples: [String] = [],
        pname: AlertPname, cardLayout: CardLayout,
        replacements: [String] = [],
        category: String? = nil, categoryHuman: String? = nil, group: String = "",
        hidden: Bool = false, muted: Bool = false, canBeMuted: Bool = true,
        hasMoreInfo: Bool = false, canBeAddedToDictionary: Bool = false
    ) {
        self.id = id
        self.rev = rev
        self.begin = begin
        self.end = end
        self.highlightBegin = highlightBegin ?? begin
        self.highlightEnd = highlightEnd ?? end
        self.highlightText = highlightText
        self.title = title
        self.details = details
        self.explanation = explanation
        self.examples = examples
        self.pname = pname
        self.cardLayout = cardLayout
        self.replacements = replacements
        self.category = category ?? pname.rawValue
        self.categoryHuman = categoryHuman ?? cardLayout.outcome.title
        self.group = group
        self.hidden = hidden
        self.muted = muted
        self.canBeMuted = canBeMuted
        self.hasMoreInfo = hasMoreInfo
        self.canBeAddedToDictionary = canBeAddedToDictionary
    }

    // MARK: - Derived predicates
    //
    // The views branch on these rather than on `pname` directly, so putting a
    // rule in a category is one line here instead of a hunt through the UI for
    // every switch that would need a new case.

    public var isSpelling: Bool { pname == .misspelled || pname == .repeatedWord }

    public var isGrammar: Bool {
        [.articleAgreement, .subjectVerbAgreement, .lowercaseSentenceStart].contains(pname)
    }

    public var isPunctuation: Bool {
        [.doubleSpace, .spaceBeforePunctuation, .missingTerminalPunctuation,
         .oxfordComma, .spaceAfterApostrophe].contains(pname)
    }

    public var isPassiveVoiceAlert: Bool { pname == .passiveVoice }

    /// True when the alert rewrites a whole sentence rather than a span.
    public var isSentenceRewrite: Bool { pname == .sentenceLength || pname == .monotonousOpeners }

    /// Inline alerts render as a compact bar rather than a card.
    public var isInline: Bool { cardLayout.group == .inline }

    public var isMiniAlert: Bool { replacements.count == 1 && explanation.isEmpty }

    public var isMuted: Bool { muted }

    /// Length of the replaced span.
    public var spanLength: Int { max(0, end - begin) }

    public var rangeDescription: String { "\(begin)..<\(end)" }

    /// The action bitmask this alert offers.
    public var actions: AlertActions {
        var mask: AlertActions = [.dismiss, .feedback]
        if !replacements.isEmpty { mask.insert(.accept) }
        if canBeMuted { mask.insert(.mute) }
        if canBeAddedToDictionary { mask.insert(.addToDictionary) }
        if hasMoreInfo || !explanation.isEmpty { mask.insert(.moreInfo) }
        return mask
    }

    /// Sort key: category priority, then document order, then id for stability.
    public func isPriorityHigherThan(_ other: Alert) -> Bool {
        if cardLayout.outcome.priority != other.cardLayout.outcome.priority {
            return cardLayout.outcome.priority < other.cardLayout.outcome.priority
        }
        if begin != other.begin { return begin < other.begin }
        return id < other.id
    }

    /// The delta that applies `replacements[index]` to a document of
    /// `documentLength` UTF-16 code units.
    public func applyDelta(replacementIndex: Int = 0, documentLength: Int) -> Delta? {
        guard replacements.indices.contains(replacementIndex) else { return nil }
        guard begin >= 0, end >= begin, end <= documentLength else { return nil }
        var delta = Delta()
        if begin > 0 { delta.retain(begin) }
        if end > begin { delta.delete(end - begin) }
        let text = replacements[replacementIndex]
        if !text.isEmpty { delta.insert(text) }
        return delta.chop()
    }

    /// Rebase this alert's spans through `delta`.
    ///
    /// Alerts are stamped with the revision they were computed against, and
    /// must be moved onto the current revision before they can be shown —
    /// checking is never instant, and the user keeps typing. Returns `nil` when
    /// the span has collapsed, i.e. the text the alert referred to is gone.
    public func rebased(through delta: Delta, newRevision: Int) -> Alert? {
        // Priority choice matters and is easy to get backwards:
        // begin uses priority == false, so text inserted exactly at the span's
        // start pushes the span right rather than being swallowed by it;
        // end uses priority == true, so text inserted exactly at the span's
        // end is left outside it rather than extending the underline.
        // Text typed strictly inside the span still moves `end`, which is what
        // keeps the suggestion covering the words it was computed for.
        let newBegin = delta.transformPosition(begin, priority: false)
        let newEnd = delta.transformPosition(end, priority: true)
        guard newEnd > newBegin else { return nil }

        var copy = self
        copy.begin = newBegin
        copy.end = newEnd
        copy.highlightBegin = delta.transformPosition(highlightBegin, priority: false)
        copy.highlightEnd = delta.transformPosition(highlightEnd, priority: true)
        guard copy.highlightEnd > copy.highlightBegin else { return nil }
        copy.rev = newRevision
        return copy
    }

    /// Whether `other` should replace this card in place rather than appear as
    /// a new one — the update-versus-replacement distinction that card state
    /// exists to support.
    public func isUpdated(by other: Alert) -> Bool {
        other.id == id || (other.pname == pname && other.begin == begin && other.end == end)
    }
}
