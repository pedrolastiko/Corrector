import XCTest
import CorrectorCore
@testable import CorrectorAppCore

/// Interface strings. Small, but the three visual defects that reached a
/// screenshot last cycle were all in here — a count disagreeing with its noun,
/// and a language name that stayed English in a French interface.
final class StringsTests: XCTestCase {

    private let en = Strings(locale: .english)
    private let fr = Strings(locale: .french)

    // MARK: - Login item

    func testTheLoginStringsAreTranslatedAndDistinct() {
        XCTAssertEqual(en.openAtLogin, "Open at Login")
        XCTAssertEqual(fr.openAtLogin, "Ouvrir au d\u{e9}marrage")
        for strings in [en, fr] {
            // Three states, three messages: if any two collided the menu
            // could not tell the user which one they are in.
            XCTAssertNotEqual(strings.openAtLogin, strings.loginNeedsApproval)
            XCTAssertNotEqual(strings.openAtLogin, strings.loginUnavailable)
            XCTAssertNotEqual(strings.loginNeedsApproval, strings.loginUnavailable)
        }
    }

    // MARK: - Clear

    func testClearAndItsUndoAreTranslated() {
        XCTAssertEqual(en.clear, "Clear")
        XCTAssertEqual(fr.clear, "Effacer")
        XCTAssertEqual(en.undoClear, "Undo clear")
        XCTAssertEqual(fr.undoClear, "Annuler l\u{2019}effacement")
    }

    func testTheClearButtonsTwoStatesAreNeverTheSameWord() {
        // The button carries both labels; if they ever collided, a user could
        // not tell whether the next click destroys or restores.
        for strings in [en, fr] {
            XCTAssertNotEqual(strings.clear, strings.undoClear)
        }
    }

    // MARK: - Agreement

    func testCountsAgreeWithTheirNoun() {
        XCTAssertEqual(en.sentenceCount(1), "1 sentence")
        XCTAssertEqual(en.sentenceCount(2), "2 sentences")
        XCTAssertEqual(fr.sentenceCount(1), "1 phrase")
        XCTAssertEqual(fr.sentenceCount(2), "2 phrases")
        XCTAssertEqual(en.wordCount(1), "1 word")
        XCTAssertEqual(fr.wordCount(0), "0 mots")
    }

    func testTheCorrectionCountAgreesInBothLanguages() {
        // French agrees the participle as well as the noun.
        XCTAssertEqual(en.quickCorrected(1), "1 correction applied")
        XCTAssertEqual(en.quickCorrected(3), "3 corrections applied")
        XCTAssertEqual(fr.quickCorrected(1), "1 correction appliquée")
        XCTAssertEqual(fr.quickCorrected(3), "3 corrections appliquées")
    }

    func testNoCountStringEverDisagrees() {
        // The generic version of the bug: any n other than 1 takes a plural,
        // and n == 1 never does.
        for n in [0, 1, 2, 11] {
            for strings in [en, fr] {
                let plural = n != 1
                XCTAssertEqual(strings.wordCount(n).hasSuffix("s"), plural,
                               "wordCount(\(n)) in \(strings.locale)")
                XCTAssertEqual(strings.sentenceCount(n).hasSuffix("s"), plural,
                               "sentenceCount(\(n)) in \(strings.locale)")
                XCTAssertEqual(strings.suggestionCount(n).hasSuffix("s"), plural,
                               "suggestionCount(\(n)) in \(strings.locale)")
            }
        }
    }

    // MARK: - Translation

    func testLanguageNamesFollowTheInterface() {
        // Regression: a French interface listed the document language as
        // "English".
        XCTAssertEqual(fr.languageName(.english), "Anglais")
        XCTAssertEqual(fr.languageName(.french), "Français")
        XCTAssertEqual(en.languageName(.french), "French")
        XCTAssertEqual(en.languageName(.english), "English")
    }

    func testTheNewShortcutStringsAreTranslated() {
        // An untranslated string shows up as the two locales agreeing. None of
        // these share a word between languages, so equality means someone
        // forgot.
        let pairs: [(String, String)] = [
            (en.quickRefusedSecureField, fr.quickRefusedSecureField),
            (en.quickNothingSelected, fr.quickNothingSelected),
            (en.quickNeedsPermission, fr.quickNeedsPermission),
            (en.quickAlreadyCorrect, fr.quickAlreadyCorrect),
            (en.quickCorrect, fr.quickCorrect),
        ]
        for (english, french) in pairs {
            XCTAssertFalse(english.isEmpty)
            XCTAssertFalse(french.isEmpty)
            XCTAssertNotEqual(english, french, "“\(english)” was never translated")
        }
    }

    func testTheRefusalNamesTheApplication() {
        XCTAssertTrue(en.quickRefusedApplication("Terminal").contains("Terminal"))
        XCTAssertTrue(fr.quickRefusedApplication("Terminal").contains("Terminal"))
        XCTAssertNotEqual(en.quickRefusedApplication("Terminal"),
                          fr.quickRefusedApplication("Terminal"))
    }

    // MARK: - Locale selection

    func testSystemLocaleFallsBackToEnglish() {
        XCTAssertEqual(UILocale.allCases.count, 2)
        XCTAssertTrue(UILocale.allCases.allSatisfy { !$0.displayName.isEmpty })
    }
}
