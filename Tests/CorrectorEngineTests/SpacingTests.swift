import XCTest
import CorrectorCore
@testable import CorrectorEngine

/// Space runs, and the apostrophe of elision.
///
/// Both of these were reported from use rather than found by a test, which is
/// the interesting part: a French document could hold any number of double
/// spaces and Corrector said nothing, because the rule that catches them was
/// written inside the English punctuation plugin. The tests here fix the
/// language dimension in place so the next shared rule cannot be filed the
/// same way by accident.
final class SpacingTests: XCTestCase {

    private func alerts(_ text: String, _ dialect: Dialect) -> [Alert] {
        CheckEngine().check(text: text, dialect: dialect).alerts
    }

    private func pnames(_ text: String, _ dialect: Dialect) -> Set<AlertPname> {
        Set(alerts(text, dialect).map(\.pname))
    }

    /// What the document becomes if the user accepts one alert.
    private func applyingFirst(_ pname: AlertPname,
                               to text: String, _ dialect: Dialect) -> String? {
        guard let alert = alerts(text, dialect).first(where: { $0.pname == pname }),
              let replacement = alert.replacements.first else { return nil }
        return (text as NSString).replacingCharacters(
            in: NSRange(location: alert.begin, length: alert.end - alert.begin),
            with: replacement)
    }

    // MARK: - Runs of spaces

    func testDoubleSpacesAreCaughtInFrench() {
        // The reported bug. This produced nothing at all before.
        XCTAssertTrue(pnames("Le chat  dort sur le tapis.", .french).contains(.doubleSpace))
    }

    func testDoubleSpacesAreStillCaughtInEnglish() {
        XCTAssertTrue(pnames("The cat  sleeps on the rug.", .american).contains(.doubleSpace))
    }

    func testEveryRunInTheLineIsReported() {
        // One alert per run: fixing the first must not hide the second.
        for dialect in [Dialect.french, .american] {
            let found = alerts("Le texte  contient  deux fautes.", dialect)
                .filter { $0.pname == .doubleSpace }
            XCTAssertEqual(found.count, 2, "\(dialect)")
        }
    }

    func testASingleSpaceIsLeftAlone() {
        XCTAssertFalse(pnames("Le chat dort sur le tapis.", .french).contains(.doubleSpace))
    }

    func testANonBreakingSpaceIsNotATypingSlip() {
        // U+00A0 is a character someone chose; only U+0020 runs collapse.
        XCTAssertFalse(
            pnames("Le chat\u{00A0}\u{00A0}dort la.", .french).contains(.doubleSpace))
    }

    func testAcceptingLeavesExactlyOneSpace() {
        XCTAssertEqual(applyingFirst(.doubleSpace, to: "Le chat   dort ici.", .french),
                       "Le chat dort ici.")
    }

    // MARK: - Runs of spaces before French double punctuation

    func testARunBeforeAFrenchMarkBecomesOneNonBreakingSpace() {
        // The collapsing rule must stand aside here: one space would still be
        // wrong in French. A single accept has to land on the right character.
        XCTAssertEqual(applyingFirst(.frenchSpacing, to: "Attention  ! Le train part.", .french),
                       "Attention\u{202F}! Le train part.")
        XCTAssertEqual(applyingFirst(.frenchSpacing, to: "Le total  : trente euros.", .french),
                       "Le total\u{00A0}: trente euros.")
    }

    func testTheTwoRulesDoNotBothClaimThatRun() {
        let found = alerts("Attention  ! Le train part.", .french)
        XCTAssertFalse(found.contains { $0.pname == .doubleSpace },
                       "the run before « ! » belongs to the typography rule alone")
    }

    func testEnglishStillCollapsesARunBeforeAMark() {
        // English has no such exemption: the space itself is the error.
        XCTAssertTrue(pnames("Ship it  ! Now please.", .american)
            .contains(where: { $0 == .doubleSpace || $0 == .spaceBeforePunctuation }))
    }

    // MARK: - The apostrophe of elision

    func testASpaceAfterTheApostropheIsCaught() {
        XCTAssertTrue(pnames("L' application ne marche pas.", .french)
            .contains(.spaceAfterApostrophe))
    }

    func testTheTypographicApostropheCountsToo() {
        XCTAssertTrue(pnames("Il m\u{2019} a dit cela hier.", .french)
            .contains(.spaceAfterApostrophe))
    }

    func testAcceptingWeldsTheWordsTogether() {
        XCTAssertEqual(applyingFirst(.spaceAfterApostrophe,
                                     to: "L' application ne marche pas.", .french),
                       "L'application ne marche pas.")
        XCTAssertEqual(applyingFirst(.spaceAfterApostrophe,
                                     to: "C\u{2019}  est fini pour aujourd'hui.", .french),
                       "C\u{2019}est fini pour aujourd'hui.")
    }

    func testTheLongerElidedFormsAreKnown() {
        for text in ["Il viendra lorsqu' il pourra venir.",
                     "Je sais qu' il est parti hier.",
                     "Nous partons aujourd' hui vers midi.",
                     "Il reste quelqu' un dans la salle."] {
            XCTAssertTrue(pnames(text, .french).contains(.spaceAfterApostrophe), text)
        }
    }

    // MARK: - What the rule must never touch
    //
    // An apostrophe followed by a space is correct far more often than not.
    // These are the cases that make the elidable-word test necessary rather
    // than decorative.

    func testAnEnglishPluralPossessiveIsNotTouched() {
        XCTAssertFalse(pnames("The dogs' owners arrived at the gate.", .american)
            .contains(.spaceAfterApostrophe))
        XCTAssertFalse(pnames("The dogs' owners arrived at the gate.", .french)
            .contains(.spaceAfterApostrophe))
    }

    func testAWordThatDoesNotElideIsNotTouched() {
        XCTAssertFalse(pnames("Les chats' sont dans le jardin.", .french)
            .contains(.spaceAfterApostrophe))
    }

    func testAnElidableLetterInsideAWordIsNotABoundary() {
        // "al' " ends in "l", but the "l" does not start a word.
        XCTAssertFalse(pnames("Le journal' est sur la table.", .french)
            .contains(.spaceAfterApostrophe))
    }

    func testAnApostropheWithNothingInFrontIsNotTouched() {
        XCTAssertFalse(pnames("' application ne marche pas.", .french)
            .contains(.spaceAfterApostrophe))
    }

    func testAnApostropheFollowedByPunctuationIsNotTouched() {
        // A word must follow, or there is nothing to weld it to.
        XCTAssertFalse(pnames("Il a dit « l' », puis rien du tout.", .french)
            .contains(.spaceAfterApostrophe))
    }

    func testACorrectElisionIsLeftAlone() {
        XCTAssertFalse(pnames("L'application fonctionne tres bien.", .french)
            .contains(.spaceAfterApostrophe))
    }

    // MARK: - Routing

    func testTheApostropheRuleIsFrenchOnly() {
        // English "I' ll" is rare, but a closing single quote after an
        // elidable letter is not: « he said 'no' to me » would be mangled.
        XCTAssertFalse(pnames("He said 'd' and then left.", .american)
            .contains(.spaceAfterApostrophe))
    }
}
