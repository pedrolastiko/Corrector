import XCTest
import CorrectorDelta
@testable import CorrectorCore

final class AlertTests: XCTestCase {

    private func alert(begin: Int, end: Int, pname: AlertPname = .misspelled,
                       replacements: [String] = ["the"]) -> Alert {
        Alert(id: 1, rev: 0, begin: begin, end: end,
              title: "Misspelled word", pname: pname,
              cardLayout: CardLayout(outcome: .correctness),
              replacements: replacements, canBeAddedToDictionary: true)
    }

    // MARK: - Action mask

    func testActionMaskIncludesAcceptWhenThereIsAReplacement() {
        XCTAssertTrue(alert(begin: 0, end: 3).actions.contains(.accept))
    }

    func testActionMaskOmitsAcceptWithoutReplacement() {
        let a = alert(begin: 0, end: 3, pname: .passiveVoice, replacements: [])
        XCTAssertFalse(a.actions.contains(.accept))
        XCTAssertTrue(a.actions.contains(.dismiss))
    }

    func testActionMaskIncludesDictionaryOnlyForSpelling() {
        XCTAssertTrue(alert(begin: 0, end: 3).actions.contains(.addToDictionary))
        var other = alert(begin: 0, end: 3, pname: .wordiness)
        other.canBeAddedToDictionary = false
        XCTAssertFalse(other.actions.contains(.addToDictionary))
    }

    // MARK: - Predicates

    func testCategoryPredicates() {
        XCTAssertTrue(alert(begin: 0, end: 3, pname: .misspelled).isSpelling)
        XCTAssertTrue(alert(begin: 0, end: 3, pname: .articleAgreement).isGrammar)
        XCTAssertTrue(alert(begin: 0, end: 3, pname: .doubleSpace).isPunctuation)
        XCTAssertTrue(alert(begin: 0, end: 3, pname: .passiveVoice).isPassiveVoiceAlert)
    }

    func testPriorityOrdersByOutcomeThenPosition() {
        let correctness = Alert(id: 1, rev: 0, begin: 50, end: 53, title: "a",
                                pname: .misspelled,
                                cardLayout: CardLayout(outcome: .correctness))
        let clarity = Alert(id: 2, rev: 0, begin: 10, end: 13, title: "b",
                            pname: .wordiness,
                            cardLayout: CardLayout(outcome: .clarity))
        XCTAssertTrue(correctness.isPriorityHigherThan(clarity))
    }

    // MARK: - applyDelta

    func testApplyDeltaProducesTheReplacement() {
        let document = Delta(text: "teh cat")
        let a = alert(begin: 0, end: 3)
        let delta = a.applyDelta(documentLength: document.length)
        XCTAssertNotNil(delta)
        XCTAssertEqual(document.compose(delta!).text, "the cat")
    }

    func testApplyDeltaRejectsOutOfBoundsSpan() {
        XCTAssertNil(alert(begin: 0, end: 99).applyDelta(documentLength: 7))
    }

    func testApplyDeltaWithEmptyReplacementDeletes() {
        let document = Delta(text: "just do it")
        let a = Alert(id: 1, rev: 0, begin: 0, end: 5, title: "Filler",
                      pname: .fillerWord,
                      cardLayout: CardLayout(outcome: .engagement),
                      replacements: [""])
        XCTAssertEqual(document.compose(a.applyDelta(documentLength: document.length)!).text,
                       "do it")
    }

    // MARK: - Rebasing

    func testRebaseShiftsSpanWhenTextInsertedBefore() {
        var edit = Delta(); edit.insert("Yesterday ")
        let moved = alert(begin: 0, end: 3).rebased(through: edit, newRevision: 2)
        XCTAssertEqual(moved?.begin, 10)
        XCTAssertEqual(moved?.end, 13)
        XCTAssertEqual(moved?.rev, 2)
    }

    func testRebaseLeavesSpanAloneWhenTextInsertedAfter() {
        var edit = Delta(); edit.retain(20); edit.insert("tail")
        let moved = alert(begin: 0, end: 3).rebased(through: edit, newRevision: 2)
        XCTAssertEqual(moved?.begin, 0)
        XCTAssertEqual(moved?.end, 3)
    }

    func testRebaseDoesNotExtendSpanForInsertAtItsEnd() {
        // Typing immediately after the underlined word must not swallow the
        // new characters into the suggestion.
        var edit = Delta(); edit.retain(3); edit.insert("XYZ")
        let moved = alert(begin: 0, end: 3).rebased(through: edit, newRevision: 2)
        XCTAssertEqual(moved?.end, 3)
    }

    func testRebaseExtendsSpanForInsertInsideIt() {
        var edit = Delta(); edit.retain(1); edit.insert("X")
        let moved = alert(begin: 0, end: 3).rebased(through: edit, newRevision: 2)
        XCTAssertEqual(moved?.begin, 0)
        XCTAssertEqual(moved?.end, 4)
    }

    func testRebaseDropsAlertWhenItsSpanIsDeleted() {
        var edit = Delta(); edit.delete(3)
        XCTAssertNil(alert(begin: 0, end: 3).rebased(through: edit, newRevision: 2))
    }

    func testRebaseAcrossEmojiUsesUTF16Units() {
        var edit = Delta(); edit.insert("🎉")       // two code units
        let moved = alert(begin: 4, end: 7).rebased(through: edit, newRevision: 2)
        XCTAssertEqual(moved?.begin, 6)
        XCTAssertEqual(moved?.end, 9)
    }
}
