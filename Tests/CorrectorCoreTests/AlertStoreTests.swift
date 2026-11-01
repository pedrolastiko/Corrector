import XCTest
import CorrectorDelta
@testable import CorrectorCore

final class AlertStoreTests: XCTestCase {

    private func make(id: Int, begin: Int, end: Int,
                      pname: AlertPname = .misspelled,
                      outcome: CardLayout.Outcome = .correctness,
                      title: String = "Misspelled word",
                      highlightText: String = "teh") -> Alert {
        Alert(id: id, rev: 0, begin: begin, end: end, highlightText: highlightText,
              title: title, pname: pname,
              cardLayout: CardLayout(outcome: outcome), replacements: ["the"],
              canBeAddedToDictionary: pname == .misspelled)
    }

    func testApplyAddsNewAlerts() {
        let store = AlertStore()
        let diff = store.apply(incoming: [make(id: 1, begin: 0, end: 3)], revision: 1)
        XCTAssertEqual(diff.added.count, 1)
        XCTAssertEqual(store.alerts.count, 1)
    }

    func testApplyRemovesVanishedAlerts() {
        let store = AlertStore()
        store.apply(incoming: [make(id: 1, begin: 0, end: 3)], revision: 1)
        let diff = store.apply(incoming: [], revision: 2)
        XCTAssertEqual(diff.removed, [1])
        XCTAssertTrue(store.alerts.isEmpty)
    }

    func testApplyUpdatesInPlaceAndKeepsIdentity() {
        // The same issue on the same span arriving again must keep its card,
        // not destroy and recreate it.
        let store = AlertStore()
        store.apply(incoming: [make(id: 1, begin: 0, end: 3)], revision: 1)

        var changed = make(id: 999, begin: 0, end: 3)
        changed.title = "Misspelled word (updated)"
        let diff = store.apply(incoming: [changed], revision: 2)

        XCTAssertTrue(diff.added.isEmpty)
        XCTAssertTrue(diff.removed.isEmpty)
        XCTAssertEqual(diff.updated.count, 1)
        XCTAssertEqual(store.alerts.first?.id, 1, "identity must survive the update")
        XCTAssertEqual(store.alerts.first?.title, "Misspelled word (updated)")
    }

    func testRebaseMovesHeldAlerts() {
        let store = AlertStore()
        store.apply(incoming: [make(id: 1, begin: 0, end: 3)], revision: 1)
        var edit = Delta(); edit.insert("hello ")
        let diff = store.rebase(through: edit, newRevision: 2)
        XCTAssertEqual(store.alerts.first?.begin, 6)
        XCTAssertEqual(diff.updated.count, 1)
        XCTAssertEqual(store.revision, 2)
    }

    func testRebaseDropsDestroyedAlerts() {
        let store = AlertStore()
        store.apply(incoming: [make(id: 1, begin: 0, end: 3)], revision: 1)
        var edit = Delta(); edit.delete(3)
        let diff = store.rebase(through: edit, newRevision: 2)
        XCTAssertEqual(diff.removed, [1])
        XCTAssertTrue(store.alerts.isEmpty)
    }

    func testMuteHidesAlertsOfThatRule() {
        let store = AlertStore()
        store.apply(incoming: [make(id: 1, begin: 0, end: 3),
                               make(id: 2, begin: 10, end: 13,
                                    pname: .wordiness, outcome: .clarity)],
                    revision: 1)
        store.mute(rule: .misspelled)
        XCTAssertEqual(store.visibleAlerts.count, 1)
        XCTAssertEqual(store.visibleAlerts.first?.pname, .wordiness)

        store.unmute(rule: .misspelled)
        XCTAssertEqual(store.visibleAlerts.count, 2)
    }

    func testMutedRulesSuppressFutureAlerts() {
        let store = AlertStore()
        store.mute(rule: .misspelled)
        store.apply(incoming: [make(id: 1, begin: 0, end: 3)], revision: 1)
        XCTAssertTrue(store.visibleAlerts.isEmpty)
    }

    func testAddToDictionaryRemovesMatchingSpellingAlerts() {
        let store = AlertStore()
        store.apply(incoming: [make(id: 1, begin: 0, end: 3, highlightText: "Corrector")],
                    revision: 1)
        store.addToDictionary("corrector")
        XCTAssertTrue(store.alerts.isEmpty)

        // And it stays suppressed on the next pass.
        store.apply(incoming: [make(id: 2, begin: 0, end: 3, highlightText: "Corrector")],
                    revision: 2)
        XCTAssertTrue(store.alerts.isEmpty)
    }

    func testRestoreReinstatesTheDictionary() {
        // A word added to the dictionary must stay added across relaunches,
        // so the store has to accept a previously saved set.
        let store = AlertStore()
        store.restore(dictionary: ["corrector"], mutedRules: [])
        store.apply(incoming: [make(id: 1, begin: 0, end: 3, highlightText: "Corrector")],
                    revision: 1)
        XCTAssertTrue(store.alerts.isEmpty)
    }

    func testRestoreReinstatesMutedRules() {
        let store = AlertStore()
        store.restore(dictionary: [], mutedRules: [.misspelled])
        store.apply(incoming: [make(id: 1, begin: 0, end: 3)], revision: 1)
        XCTAssertTrue(store.visibleAlerts.isEmpty)
    }

    func testRestoreMutesAlertsAlreadyHeld() {
        let store = AlertStore()
        store.apply(incoming: [make(id: 1, begin: 0, end: 3)], revision: 1)
        XCTAssertEqual(store.visibleAlerts.count, 1)
        store.restore(dictionary: [], mutedRules: [.misspelled])
        XCTAssertTrue(store.visibleAlerts.isEmpty)
    }

    func testRestoreIsCaseInsensitiveForDictionaryWords() {
        let store = AlertStore()
        store.restore(dictionary: ["CORRECTOR"], mutedRules: [])
        store.apply(incoming: [make(id: 1, begin: 0, end: 3, highlightText: "corrector")],
                    revision: 1)
        XCTAssertTrue(store.alerts.isEmpty)
    }

    func testVisibleAlertsAreSortedByPriority() {
        let store = AlertStore()
        store.apply(incoming: [
            make(id: 1, begin: 80, end: 85, pname: .wordiness, outcome: .clarity),
            make(id: 2, begin: 40, end: 45),
            make(id: 3, begin: 10, end: 15),
        ], revision: 1)
        XCTAssertEqual(store.visibleAlerts.map(\.id), [3, 2, 1])
    }

    func testCardLayoutGroupCounts() {
        let store = AlertStore()
        store.apply(incoming: [
            make(id: 1, begin: 0, end: 3),
            make(id: 2, begin: 10, end: 13),
            make(id: 3, begin: 20, end: 23, pname: .wordiness, outcome: .clarity),
        ], revision: 1)
        let counts = store.cardLayoutGroupCounts()
        XCTAssertEqual(counts[.correctness], 2)
        XCTAssertEqual(counts[.clarity], 1)
    }

    func testSelectionClearsWhenSelectedAlertDisappears() {
        let store = AlertStore()
        store.apply(incoming: [make(id: 1, begin: 0, end: 3)], revision: 1)
        store.select(id: 1)
        XCTAssertEqual(store.selectedID, 1)
        store.apply(incoming: [], revision: 2)
        XCTAssertNil(store.selectedID)
    }
}
