import XCTest
import CorrectorCore
import CorrectorEngine
import CorrectorDelta
@testable import CorrectorSession

final class SessionTests: XCTestCase {

    private func started(text: String = "",
                         supports: FeatureSet = .all,
                         transient: Bool = false) -> CheckSession {
        let session = CheckSession(engine: CheckEngine(features: supports))
        session.handle(.startSession(.init(clientSupports: supports,
                                           documentIdentifier: "test-doc",
                                           documentIdentifierIsTransient: transient,
                                           text: text)))
        return session
    }

    // MARK: - Lifecycle

    func testSessionStartsAndReportsStarted() {
        let session = CheckSession()
        let replies = session.handle(.startSession(.init(documentIdentifier: "d")))
        XCTAssertEqual(session.state, .active)
        XCTAssertTrue(replies.contains { if case.started = $0 { return true }; return false })
    }

    func testStartingTwiceIsAnError() {
        let session = started()
        let replies = session.handle(.startSession(.init(documentIdentifier: "d")))
        XCTAssertEqual(replies, [.error(.alreadyStarted)])
    }

    func testChangesetBeforeStartIsRejected() {
        let session = CheckSession()
        var edit = Delta(); edit.insert("x")
        XCTAssertEqual(session.handle(.submitChangeset(id: 0, revision: 0, changeSet: edit)),
                       [.error(.notStarted)])
    }

    func testPingPong() {
        XCTAssertEqual(started().handle(.ping), [.pong])
    }

    // MARK: - Capability negotiation

    func testAllowedFeaturesAreTheIntersection() {
        let session = started(supports: [.spelling, .grammar])
        XCTAssertEqual(session.allowedFeatures, [.spelling, .grammar])
    }

    func testTransientFieldGetsCorrectnessChecksOnly() {
        // A transient surface narrows the check set to correctness.
        let session = started(text: "In order to win we must try very hard.",
                              supports: .all, transient: true)
        XCTAssertEqual(session.allowedFeatures, .correctnessOnly)
        XCTAssertFalse(session.alertStore.visibleAlerts.contains { $0.pname == .wordiness })
    }

    func testToggleChecksCannotExceedAllowedFeatures() {
        let session = started(text: "teh cat", supports: [.spelling])
        session.handle(.toggleChecks(.all))
        XCTAssertTrue(session.alertStore.visibleAlerts.allSatisfy { $0.isSpelling })
    }

    // MARK: - Changesets

    func testStaleRevisionIsRejected() {
        let session = started(text: "hello")
        var edit = Delta(); edit.insert("x")
        let replies = session.handle(.submitChangeset(id: 0, revision: 99, changeSet: edit))
        guard case.error(.staleRevision(let expected, let received))? = replies.first else {
            return XCTFail("expected a stale-revision error, got \(replies)")
        }
        XCTAssertEqual(expected, session.revision)
        XCTAssertEqual(received, 99)
    }

    func testOversizedChangesetIsRejected() {
        let session = started(text: "hello")
        var edit = Delta(); edit.insert(String(repeating: "x", count: 100_000))
        guard case.error(.messageTooLarge)? = session.handle(
            .submitChangeset(id: 0, revision: session.revision, changeSet: edit)).first
        else { return XCTFail("expected a size error") }
    }

    func testTypingAdvancesRevisionAndRechecks() {
        let session = started(text: "The cat sat.")
        let before = session.revision
        session.type("teh ")
        XCTAssertEqual(session.revision, before + 1)
        XCTAssertTrue(session.alertStore.visibleAlerts.contains { $0.pname == .misspelled })
    }

    // MARK: - Rebasing

    func testAlertsSurviveAnEditElsewhereAndKeepTheirIdentity() {
        let session = started(text: "teh report is ready.")
        guard let original = session.alertStore.visibleAlerts.first else {
            return XCTFail("expected a spelling alert")
        }
        XCTAssertEqual(original.begin, 0)

        var edit = Delta(); edit.insert("Yesterday ")
        session.handle(.submitChangeset(id: 1, revision: session.revision, changeSet: edit))

        let moved = session.alertStore.alert(id: original.id)
        XCTAssertNotNil(moved, "the card must survive the edit")
        XCTAssertEqual(moved?.begin, 10)
        XCTAssertEqual(session.text.utf16Slice(moved!.begin, moved!.end), "teh")
    }

    func testAlertDisappearsWhenTheUserFixesItByHand() {
        let session = started(text: "teh report is ready.")
        XCTAssertFalse(session.alertStore.visibleAlerts.isEmpty)

        var edit = Delta(); edit.delete(3); edit.insert("The")
        session.handle(.submitChangeset(id: 1, revision: session.revision, changeSet: edit))

        XCTAssertFalse(session.alertStore.visibleAlerts.contains { $0.pname == .misspelled })
    }

    // MARK: - User actions

    func testAcceptAppliesTheReplacement() {
        let session = started(text: "teh report is ready.")
        guard let alert = session.alertStore.visibleAlerts.first else {
            return XCTFail("expected an alert")
        }
        session.accept(alertID: alert.id)
        // One action, one change: the spelling fix lands now. Capitalising the
        // sentence is a separate suggestion that only exists once "teh" has
        // become a real word, so it appears on the next pass.
        XCTAssertEqual(session.text, "the report is ready.")
        XCTAssertNil(session.alertStore.alert(id: alert.id))
        XCTAssertTrue(session.alertStore.visibleAlerts
            .contains { $0.pname == .lowercaseSentenceStart })

        session.acceptAll()
        XCTAssertEqual(session.text, "The report is ready.")
    }

    func testDismissRemovesWithoutChangingText() {
        let session = started(text: "teh report is ready.")
        guard let alert = session.alertStore.visibleAlerts.first else {
            return XCTFail("expected an alert")
        }
        session.handle(.userAction(alertID: alert.id, action: .dismiss))
        XCTAssertEqual(session.text, "teh report is ready.")
        XCTAssertNil(session.alertStore.alert(id: alert.id))
    }

    func testMarkingOffensiveMutesTheRule() {
        let session = started(text: "teh cat and teh dog.")
        guard let alert = session.alertStore.visibleAlerts.first else {
            return XCTFail("expected an alert")
        }
        session.handle(.userAction(alertID: alert.id, action: .offensive))
        XCTAssertTrue(session.alertStore.visibleAlerts.isEmpty)
    }

    func testViewSelectsTheAlert() {
        let session = started(text: "teh report is ready.")
        let id = session.alertStore.visibleAlerts.first!.id
        session.handle(.userAction(alertID: id, action: .view))
        XCTAssertEqual(session.alertStore.selectedID, id)
    }

    func testAcceptAllConverges() {
        let session = started(text:
            "teh report was recieved by Sam . In order to fix this we must try very hard.")
        let applied = session.acceptAll()
        XCTAssertGreaterThan(applied, 0)
        // Everything that remains must be advisory, with nothing to apply.
        XCTAssertTrue(session.alertStore.visibleAlerts.allSatisfy { $0.replacements.isEmpty })
    }

    func testAcceptAllLeavesTextWellFormed() {
        let session = started(text: "teh  cat was recieved by a honest man .")
        session.acceptAll()
        XCTAssertFalse(session.text.contains("  "), "no double spaces: \(session.text)")
        XCTAssertFalse(session.text.contains(" ."), "no space before full stop: \(session.text)")
        XCTAssertTrue(session.text.hasPrefix("The"))
    }

    // MARK: - replaceAll

    func testReplaceAllDiffsToAChangeset() {
        let session = started(text: "the quick brown fox")
        session.replaceAll(with: "the quick red fox")
        XCTAssertEqual(session.text, "the quick red fox")
        XCTAssertEqual(session.revision, 2)
    }

    func testReplaceAllWithIdenticalTextIsANoOp() {
        let session = started(text: "unchanged text here")
        let before = session.revision
        XCTAssertTrue(session.replaceAll(with: "unchanged text here").isEmpty)
        XCTAssertEqual(session.revision, before)
    }

    // MARK: - Reporting

    func testFinishedCarriesScoresAndStats() {
        let session = CheckSession()
        let replies = session.handle(.startSession(.init(documentIdentifier: "d",
                                                         text: "The cat sat on the mat.")))
        guard let finished = replies.compactMap({ reply -> ServerMessage.Finished? in
            if case.finished(let f) = reply { return f }
            return nil
        }).last else { return XCTFail("expected a finished message") }

        XCTAssertEqual(finished.revision, session.revision)
        XCTAssertEqual(finished.stats.words, 6)
        XCTAssertEqual(finished.scores.generalScore, 100)
    }

    func testTextStatsRequest() {
        let session = started(text: "One two three.")
        guard case.textInfo(let stats)? = session.handle(.requestTextStats).first else {
            return XCTFail("expected text info")
        }
        XCTAssertEqual(stats.words, 3)
    }

    // MARK: - End to end

    func testFullEditLoopStaysConsistent() {
        let session = started(text: "teh report is ready.")
        for word in ["Also ", "very ", "basically "] {
            session.type(word)
            // Every alert must still point at live text.
            for alert in session.alertStore.visibleAlerts {
                XCTAssertLessThanOrEqual(alert.end, session.text.utf16.count)
                XCTAssertLessThanOrEqual(alert.begin, alert.end)
            }
        }
        session.acceptAll()
        XCTAssertFalse(session.text.isEmpty)
        XCTAssertLessThanOrEqual(session.alertStore.visibleAlerts.count, 3)
    }
}

/// Guards the feature set the "Correct Selection" Service runs with.
///
/// The Service lives in the app target and cannot be imported here, but the
/// behaviour that matters is the engine's, and that is testable.
final class CorrectionOnlyFeatureTests: XCTestCase {

    /// Mirror of `ServiceProvider.correctionFeatures`.
    private let correctionOnly: FeatureSet =
        [.spelling, .grammar, .punctuation, .styleGuide]

    private func correct(_ text: String) -> String {
        let session = CheckSession(engine: CheckEngine(features: correctionOnly))
        session.handle(.startSession(.init(clientSupports: correctionOnly,
                                           dialect: .auto,
                                           documentIdentifier: "service",
                                           text: text)))
        session.acceptAll()
        return session.text
    }

    func testCorrectingFrenchKeepsTheWritersIntensifier() {
        // Regression: applying every suggestion fixed "tres" to "très" and
        // then deleted it as a weak intensifier, so "c'est tres bien" came
        // back as "c'est bien". Correcting must not restyle.
        let result = correct("c'est tres bien")
        XCTAssertTrue(result.contains("très"), "obtenu: \(result)")
    }

    func testCorrectingEnglishKeepsTheWritersIntensifier() {
        XCTAssertTrue(correct("teh result is very good.").contains("very"))
    }

    func testCorrectingStillFixesObjectiveErrors() {
        XCTAssertEqual(correct("teh report was recieved by a honest man ."),
                       "The report was received by an honest man.")
    }

    func testCorrectingAppliesFrenchTypography() {
        let result = correct("le ami a dit: \"bonjour\".")
        XCTAssertTrue(result.contains("L'ami") || result.contains("L\u{2019}ami"),
                      "élision attendue, obtenu: \(result)")
        XCTAssertTrue(result.contains("\u{00AB}"), "guillemets attendus: \(result)")
    }

    func testCorrectingLeavesWordinessAlone() {
        // "In order to" is a clarity suggestion, which this set excludes.
        XCTAssertTrue(correct("In order to win, we must try.").contains("In order to"))
    }
}
