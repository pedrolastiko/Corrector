import XCTest
import CorrectorCore
@testable import CorrectorEngine

final class EngineTests: XCTestCase {

    private let engine = CheckEngine()

    private func alerts(_ text: String, features: FeatureSet = .all) -> [Alert] {
        CheckEngine(features: features).check(text: text).alerts
    }

    private func pnames(_ text: String, features: FeatureSet = .all) -> Set<AlertPname> {
        Set(alerts(text, features: features).map(\.pname))
    }

    // MARK: - Spelling

    func testCatchesMisspelling() {
        let found = alerts("teh cat sat on the mat.", features: .spelling)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.pname, .misspelled)
        XCTAssertEqual(found.first?.replacements.first, "the")
        XCTAssertEqual(found.first?.begin, 0)
        XCTAssertEqual(found.first?.end, 3)
    }

    func testMisspellingPreservesCapitalisation() {
        let found = alerts("Teh cat sat.", features: .spelling)
        XCTAssertEqual(found.first?.replacements.first, "The")
    }

    func testCatchesRepeatedWord() {
        XCTAssertTrue(pnames("I saw the the cat.", features: .spelling).contains(.repeatedWord))
    }

    func testDoesNotFlagRepeatedWordAcrossPunctuation() {
        // "No, no" is deliberate repetition, not a typo: the words are
        // separated by punctuation, not just whitespace.
        XCTAssertFalse(pnames("No, no, I disagree.", features: .spelling)
            .contains(.repeatedWord))
    }

    func testFlagsRepeatedWordSeparatedOnlyByWhitespace() {
        XCTAssertTrue(pnames("It is is broken.", features: .spelling)
            .contains(.repeatedWord))
    }

    func testCleanTextProducesNoSpellingAlerts() {
        XCTAssertTrue(alerts("The cat sat on the mat.", features: .spelling).isEmpty)
    }

    // MARK: - Grammar

    func testArticleAgreement() {
        XCTAssertTrue(pnames("A honest man.", features: .grammar).contains(.articleAgreement))
        XCTAssertTrue(pnames("An university.", features: .grammar).contains(.articleAgreement))
    }

    func testArticleAgreementAcceptsCorrectUsage() {
        XCTAssertFalse(pnames("An honest man met a university dean.", features: .grammar)
            .contains(.articleAgreement))
    }

    func testSubjectVerbAgreement() {
        XCTAssertTrue(pnames("They was late.", features: .grammar)
            .contains(.subjectVerbAgreement))
        XCTAssertTrue(pnames("He have arrived.", features: .grammar)
            .contains(.subjectVerbAgreement))
    }

    func testSentenceCapitalisation() {
        XCTAssertTrue(pnames("the cat sat.", features: .grammar)
            .contains(.lowercaseSentenceStart))
        XCTAssertFalse(pnames("The cat sat.", features: .grammar)
            .contains(.lowercaseSentenceStart))
    }

    // MARK: - Punctuation

    func testDoubleSpace() {
        let found = alerts("One  two.", features: .punctuation)
        XCTAssertEqual(found.first?.pname, .doubleSpace)
        XCTAssertEqual(found.first?.replacements.first, " ")
    }

    func testSpaceBeforePunctuation() {
        XCTAssertTrue(pnames("Really ? Yes.", features: .punctuation)
            .contains(.spaceBeforePunctuation))
    }

    func testMissingTerminalPunctuationOnLongSentence() {
        XCTAssertTrue(pnames("We should ship this release on Tuesday morning",
                             features: .punctuation)
                                 .contains(.missingTerminalPunctuation))
    }

    func testShortHeadingIsNotFlaggedForMissingPunctuation() {
        XCTAssertFalse(pnames("Quarterly update", features: .punctuation)
            .contains(.missingTerminalPunctuation))
    }

    // MARK: - Clarity

    func testWordyPhrase() {
        let found = alerts("In order to win, we must try.", features: .clarity)
        XCTAssertEqual(found.first?.pname, .wordiness)
        XCTAssertEqual(found.first?.replacements.first, "to")
    }

    func testWordyPhraseRequiresWordBoundaries() {
        XCTAssertFalse(pnames("Reprioritisation matters.", features: .clarity)
            .contains(.wordiness))
    }

    func testPassiveVoice() {
        XCTAssertTrue(pnames("The report was written by Sam.", features: .clarity)
            .contains(.passiveVoice))
    }

    func testPassiveVoiceToleratesAnAdverb() {
        XCTAssertTrue(pnames("The bug was quickly resolved by Priya.", features: .clarity)
            .contains(.passiveVoice))
    }

    func testActiveVoiceIsNotFlagged() {
        XCTAssertFalse(pnames("Sam wrote the report.", features: .clarity)
            .contains(.passiveVoice))
    }

    func testCommonFalseFriendsAreNotPassive() {
        XCTAssertFalse(pnames("The speed is indeed high.", features: .clarity)
            .contains(.passiveVoice))
    }

    func testNominalisation() {
        XCTAssertTrue(pnames("The implementation of the plan stalled.", features: .clarity)
            .contains(.nominalization))
    }

    // MARK: - Engagement

    func testFillerWord() {
        XCTAssertTrue(pnames("We basically shipped it.", features: .engagement)
            .contains(.fillerWord))
    }

    func testFillerDeletionAbsorbsTheFollowingSpace() {
        let found = alerts("We basically shipped it.", features: .engagement)
        guard let filler = found.first(where: { $0.pname == .fillerWord }) else {
            return XCTFail("expected a filler alert")
        }
        // The replaced span must include the trailing space so accepting the
        // suggestion does not leave "We shipped".
        XCTAssertEqual(filler.end - filler.begin, "basically ".utf16.count)
    }

    func testWeakIntensifier() {
        XCTAssertTrue(pnames("It was very good.", features: .engagement)
            .contains(.weakIntensifier))
    }

    func testLongSentence() {
        let long = "We " + String(repeating: "really ", count: 35) + "shipped it."
        XCTAssertTrue(pnames(long, features: .engagement).contains(.sentenceLength))
    }

    func testRepetitiveOpeners() {
        let text = "The team shipped. The build passed. The users cheered."
        XCTAssertTrue(pnames(text, features: .engagement).contains(.monotonousOpeners))
    }

    func testVariedOpenersAreNotFlagged() {
        let text = "The team shipped. Users cheered. Everything held."
        XCTAssertFalse(pnames(text, features: .engagement).contains(.monotonousOpeners))
    }

    // MARK: - Style guide and inclusivity

    func testSerialComma() {
        XCTAssertTrue(pnames("We shipped red, white and blue.", features: .styleGuide)
            .contains(.oxfordComma))
    }

    func testSerialCommaNeedsAList() {
        XCTAssertFalse(pnames("Sam and Priya shipped it.", features: .styleGuide)
            .contains(.oxfordComma))
    }

    func testInclusiveLanguage() {
        let found = alerts("The chairman updated the whitelist.", features: .inclusivity)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(Set(found.flatMap(\.replacements)), ["chair", "allowlist"])
    }

    // MARK: - Engine behaviour

    func testFeatureFlagsDisableChecks() {
        // The enabled set controls what is produced.
        let text = "teh report was written by Sam."
        XCTAssertFalse(alerts(text, features: .spelling).isEmpty)
        XCTAssertTrue(alerts(text, features: .inclusivity).isEmpty)
    }

    func testOverlappingAlertsAreResolvedByPriority() {
        // "teh" would attract both a spelling and (hypothetically) a style
        // alert; only one underline may cover a given span.
        let found = alerts("teh teh teh.", features: .all)
        for (a, b) in zip(found, found.dropFirst()) {
            XCTAssertLessThanOrEqual(a.end, b.begin, "alerts must not overlap")
        }
    }

    func testAlertIDsAreStableAcrossRuns() {
        let first = engine.check(text: "teh cat sat.").alerts
        let second = engine.check(text: "teh cat sat.").alerts
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testAlertIDsAreDeterministicPerRuleAndSpan() {
        XCTAssertEqual(CheckEngine.stableID(pname: .misspelled, begin: 0, end: 3),
                       CheckEngine.stableID(pname: .misspelled, begin: 0, end: 3))
        XCTAssertNotEqual(CheckEngine.stableID(pname: .misspelled, begin: 0, end: 3),
                          CheckEngine.stableID(pname: .wordiness, begin: 0, end: 3))
        XCTAssertNotEqual(CheckEngine.stableID(pname: .misspelled, begin: 0, end: 3),
                          CheckEngine.stableID(pname: .misspelled, begin: 4, end: 7))
    }

    func testAlertIDsArePositive() {
        for pname in AlertPname.allCases {
            XCTAssertGreaterThan(CheckEngine.stableID(pname: pname, begin: 0, end: 1), 0)
        }
    }

    func testCleanDocumentScoresWell() {
        let result = engine.check(text:
            "The deployment finished at noon. We rolled it out to twelve regions "
          + "and watched the error rate for an hour.")
        XCTAssertTrue(result.alerts.isEmpty, "unexpected: \(result.alerts.map(\.title))")
        XCTAssertEqual(result.scores.generalScore, 100)
    }

    // MARK: - Offsets

    func testOffsetsAreUTF16AndSliceCorrectly() {
        let text = "We shipped it 🎉🎉 and teh team celebrated."
        let found = alerts(text, features: .spelling)
        XCTAssertEqual(found.count, 1)
        let alert = found[0]
        XCTAssertEqual(alert.begin, 23)
        XCTAssertEqual(text.utf16Slice(alert.begin, alert.end), "teh")
        XCTAssertEqual(alert.highlightText, "teh")
    }

    func testEveryAlertSpanIsWithinTheDocument() {
        let text = "teh café María 🎉 was writen by a honest  man."
        for alert in alerts(text) {
            XCTAssertGreaterThanOrEqual(alert.begin, 0)
            XCTAssertLessThanOrEqual(alert.end, text.utf16.count)
            XCTAssertLessThanOrEqual(alert.begin, alert.end)
            XCTAssertLessThanOrEqual(alert.highlightEnd, text.utf16.count)
        }
    }
}

final class RenderingHelpersTests: XCTestCase {
    // Ordinals are rendered by the CLI; the rule is easy to get wrong for the
    // 11–13 range, so it is pinned here.
    func testOrdinalSuffixes() {
        let expected: [Int: String] = [
            1: "1st", 2: "2nd", 3: "3rd", 4: "4th",
            11: "11th", 12: "12th", 13: "13th",
            21: "21st", 22: "22nd", 23: "23rd",
            83: "83rd", 100: "100th", 111: "111th",
        ]
        for (value, text) in expected {
            XCTAssertEqual(ordinalForTest(value), text)
        }
    }

    /// Mirror of `Render.ordinal`, which lives in the executable target and so
    /// cannot be imported by a test target.
    private func ordinalForTest(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}
