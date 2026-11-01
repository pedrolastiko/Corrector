import XCTest
import CorrectorCore
import CorrectorEngine
@testable import CorrectorAppCore

/// What the global shortcut and the Services menu are each allowed to change.
///
/// Every test here injects the curated table rather than the system
/// dictionaries, so the vocabulary is fixed and the assertions survive a macOS
/// update.
final class SelectionCorrectorTests: XCTestCase {

    private func corrector(_ features: FeatureSet,
                           _ dialect: Dialect = .american) -> SelectionCorrector {
        SelectionCorrector(features: features, dialect: dialect) {
            CheckEngine(features: $0)
        }
    }

    // MARK: - The line between mechanical and reviewed

    func testMechanicalFixesSpelling() {
        let outcome = corrector(SelectionCorrector.mechanical).correct("teh cat")
        XCTAssertEqual(outcome.text, "the cat")
        XCTAssertEqual(outcome.applied, 1)
        XCTAssertTrue(outcome.changed)
    }

    func testMechanicalLeavesGrammarAlone() {
        // "a apple" is wrong, and the grammar rule knows it. It still must not
        // fire here: this text is being replaced in an application the user is
        // looking at, where a wrong guess rewrites their sentence unseen.
        let outcome = corrector(SelectionCorrector.mechanical).correct("teh apple")
        XCTAssertEqual(outcome.text, "the apple")

        let both = corrector(SelectionCorrector.mechanical).correct("ate a apple")
        XCTAssertFalse(both.changed, "the article rule belongs to .grammar")
        XCTAssertEqual(both.text, "ate a apple")
    }

    func testReviewedDoesFixGrammar() {
        // The same sentence through the Services menu, where the user is
        // looking at the selection they right-clicked.
        let outcome = corrector(SelectionCorrector.reviewed).correct("ate a apple")
        XCTAssertEqual(outcome.text, "ate an apple")
    }

    // MARK: - A selection is a fragment

    func testASelectionIsNotCapitalised() {
        // Dragging over four words in the middle of a paragraph and pressing
        // the shortcut must not come back with a capital letter welded on.
        let outcome = corrector(SelectionCorrector.reviewed).correct("ate a apple")
        XCTAssertEqual(outcome.text.first, "a",
                       "the sentence-start rule has no business on a fragment")
    }

    func testASelectionGetsNoTerminalFullStop() {
        let outcome = corrector(SelectionCorrector.mechanical).correct("teh cat ate teh fish")
        XCTAssertFalse(outcome.text.hasSuffix("."),
                       "got \(outcome.text)")
    }

    func testTheFragmentRulesCanBeTurnedBackOnForAWholeDocument() {
        // Inside Corrector's own window the text really is the whole document,
        // so the same two rules are correct there. The exclusion is a
        // parameter, not a deletion.
        let whole = SelectionCorrector(features: SelectionCorrector.reviewed,
                                       dialect: .american,
                                       excludedRules: []) { CheckEngine(features: $0) }
        XCTAssertEqual(whole.correct("ate a apple").text.first, "A")
    }

    func testNeitherSetRewritesForStyle() {
        // Clarity and engagement are excluded from both: someone asking to fix
        // typos has not asked for their voice to be edited.
        XCTAssertFalse(SelectionCorrector.mechanical.contains(.clarity))
        XCTAssertFalse(SelectionCorrector.mechanical.contains(.engagement))
        XCTAssertFalse(SelectionCorrector.reviewed.contains(.clarity))
        XCTAssertFalse(SelectionCorrector.reviewed.contains(.engagement))
    }

    func testMechanicalIsASubsetOfReviewed() {
        XCTAssertTrue(SelectionCorrector.reviewed.contains(SelectionCorrector.mechanical),
                      "the shortcut must never do something the menu would not")
    }

    // MARK: - Outcomes

    func testCleanTextReportsNoChange() {
        let outcome = corrector(SelectionCorrector.mechanical).correct("The cat sat down.")
        XCTAssertFalse(outcome.changed)
        XCTAssertEqual(outcome.applied, 0)
        XCTAssertEqual(outcome.text, "The cat sat down.")
    }

    func testCorrectingIsIdempotent() {
        // The shortcut can be pressed twice. The second press must be a no-op,
        // not a second round of edits on already-corrected text.
        let first = corrector(SelectionCorrector.mechanical).correct("teh cat")
        let second = corrector(SelectionCorrector.mechanical).correct(first.text)
        XCTAssertFalse(second.changed)
        XCTAssertEqual(second.text, first.text)
    }

    func testEmptySelectionIsHarmless() {
        let outcome = corrector(SelectionCorrector.mechanical).correct("")
        XCTAssertFalse(outcome.changed)
        XCTAssertEqual(outcome.text, "")
    }

    func testCountIsReported() {
        let outcome = corrector(SelectionCorrector.mechanical).correct("teh cat ate teh fish")
        XCTAssertEqual(outcome.applied, 2, "two spellings, and nothing else")
        XCTAssertEqual(outcome.text, "the cat ate the fish")
    }

    // MARK: - French

    func testFrenchTypographyIsMechanical() {
        // Spacing before double punctuation is a typesetting rule, not a
        // judgement call, so the shortcut may apply it.
        let outcome = corrector(SelectionCorrector.mechanical, .french)
            .correct("Bonjour; ça va?")
        XCTAssertTrue(outcome.changed)
        XCTAssertTrue(outcome.text.contains("\u{202F};"),
                      "expected a narrow no-break space before the semicolon, got \(outcome.text)")
        XCTAssertTrue(outcome.text.contains("\u{202F}?"),
                      "expected a narrow no-break space before the question mark, got \(outcome.text)")
    }

    func testFrenchQuotationMarksAreNotMechanical() {
        // Converting "…" to «…» is a house-style choice. It belongs to
        // .styleGuide, which the shortcut does not carry.
        let mechanical = corrector(SelectionCorrector.mechanical, .french)
            .correct("Il a dit \"bonjour\" hier")
        XCTAssertFalse(mechanical.text.contains("«"))

        let reviewed = corrector(SelectionCorrector.reviewed, .french)
            .correct("Il a dit \"bonjour\" hier")
        XCTAssertTrue(reviewed.text.contains("«"),
                      "the reviewed set should still apply it, got \(reviewed.text)")
    }
}
