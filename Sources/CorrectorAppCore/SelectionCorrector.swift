import Foundation
import CorrectorCore
import CorrectorEngine
import CorrectorSession

/// The result of correcting a selection.
public struct SelectionCorrection: Equatable, Sendable {
    public let text: String
    /// How many suggestions were applied.
    public let applied: Int
    public var changed: Bool { applied > 0 && text != original }
    let original: String

    init(original: String, text: String, applied: Int) {
        self.original = original
        self.text = text
        self.applied = applied
    }
}

/// Corrects a span of text taken from somewhere outside the app's own window.
///
/// Extracted from `QuickCorrect` and `ServiceProvider`, which had grown two
/// copies of the same twelve lines. Having it here, in a library, is the
/// difference between a rule being asserted in a test and a rule being
/// something I checked once by hand in TextEdit.
public struct SelectionCorrector {

    /// What may be applied without the user seeing it first.
    ///
    /// Spelling and punctuation only. Every rule behind those two flags is
    /// mechanical — a word is in the dictionary or it is not, a sentence ends
    /// with a mark or it does not, French takes a narrow no-break space before
    /// a semicolon or it does not. Nothing in them depends on what the writer
    /// meant.
    ///
    /// Grammar and style are a different kind of claim. `articleAgreement`,
    /// `subjectVerbAgreement` and the engagement rules are heuristics over a
    /// sentence they cannot parse, and they are sometimes wrong. Being wrong
    /// inside Corrector's own window costs a glance; being wrong through the
    /// global shortcut silently rewrites a sentence in someone else's
    /// document, and they may never see the version they typed. That
    /// asymmetry — not the rules' accuracy — is what sets this line.
    public static let mechanical: FeatureSet = [.spelling, .punctuation]

    /// What may be applied when the user is looking at the result.
    ///
    /// The Services menu entry is a deliberate, per-invocation act on a
    /// visible selection in a document the user has open, so it can afford
    /// more than the shortcut. It still excludes clarity and engagement:
    /// someone asking to fix typos has not asked for their voice to be edited.
    public static let reviewed: FeatureSet =
        [.spelling, .grammar, .punctuation, .styleGuide]

    /// Rules that are right about a document and wrong about a selection.
    ///
    /// Both of these reason about sentence boundaries, and a selection has
    /// none it can trust: whatever the user dragged over starts and ends
    /// wherever they released the mouse. Correcting "teh cat ate teh fish"
    /// out of the middle of a paragraph should not come back as "The cat ate
    /// the fish." with a capital and a full stop welded on — and it did,
    /// until a test asked.
    ///
    /// They stay enabled inside Corrector's own window, where the text really
    /// is the whole document.
    public static let unsafeOnAFragment: Set<AlertPname> = [
        .missingTerminalPunctuation,
        .lowercaseSentenceStart,
    ]

    let features: FeatureSet
    let dialect: Dialect
    let excludedRules: Set<AlertPname>
    private let makeEngine: (FeatureSet) -> CheckEngine

    /// - Parameter engine: how to build the checker. Defaults to the system
    ///   dictionaries, which is what the app wants and what a test cannot
    ///   have: `NSSpellChecker` answers differently between macOS releases, so
    ///   tests inject the curated table and assert on a fixed vocabulary.
    public init(features: FeatureSet = SelectionCorrector.mechanical,
                dialect: Dialect = .auto,
                excludedRules: Set<AlertPname> = SelectionCorrector.unsafeOnAFragment,
                engine: @escaping (FeatureSet) -> CheckEngine = {
                    CheckEngine.system(features: $0)
                }) {
        self.features = features
        self.dialect = dialect
        self.excludedRules = excludedRules
        self.makeEngine = engine
    }

    public func correct(_ text: String, origin: String = "selection") -> SelectionCorrection {
        let session = CheckSession(engine: makeEngine(features))
        session.handle(.startSession(.init(
            clientSupports: features,
            // Always detect. A selection grabbed from another application has
            // no relationship to the dialect chosen for the document in
            // Corrector's own window.
            dialect: dialect,
            documentIdentifier: DocumentID.derive(application: "Corrector",
                                                  window: origin,
                                                  field: "selection").value,
            // Not transient: the user invoked this deliberately and wants the
            // full rule set, not the reduced one a throwaway field would get.
            documentIdentifierIsTransient: false,
            application: origin,
            domain: "general",
            text: text)))
        let applied = acceptEligible(in: session)
        return SelectionCorrection(original: text, text: session.text, applied: applied)
    }

    /// `CheckSession.acceptAll()` with the fragment-unsafe rules held back.
    ///
    /// Re-resolves the next candidate every round rather than iterating a
    /// snapshot, because accepting one suggestion shifts the spans of all the
    /// others — the session rebases them, and a stale list would apply the
    /// second fix at the wrong offset.
    private func acceptEligible(in session: CheckSession) -> Int {
        var applied = 0
        while applied < 500 {
            guard let next = session.alertStore.visibleAlerts.first(where: {
                !$0.replacements.isEmpty && !excludedRules.contains($0.pname)
            }) else { break }
            _ = session.accept(alertID: next.id)
            applied += 1
        }
        return applied
    }
}
