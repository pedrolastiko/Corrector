import XCTest
@testable import CorrectorAppCore

/// The version shown in the app, and the notes behind it.
final class ReleaseTests: XCTestCase {

    func testTheDisplayedVersionIsBuiltFromItsParts() {
        XCTAssertEqual(Release.display, "beta 0.5.1")
        XCTAssertFalse(Release.version.isEmpty)
    }

    func testDisplayDropsTheStageOnceThereIsNoneToQualify() {
        // The shape of the string must not depend on `stage` being non-empty,
        // because the day it is cleared is the day nobody is looking at this.
        XCTAssertFalse(Release.display.hasSuffix(" "))
        XCTAssertFalse(Release.display.hasPrefix(" "))
    }

    func testTheProtocolVersionAgreesWithTheDisplayedOne() {
        // The handshake constant and the footer are two views of one build.
        // They were 1.0.0 and "pre-release" at the same time before this.
        XCTAssertTrue(Release.protocolVersion.hasPrefix(Release.version),
                      "\(Release.protocolVersion) does not match \(Release.version)")
        XCTAssertTrue(Release.protocolVersion.contains(Release.stage),
                      "\(Release.protocolVersion) does not mention the \(Release.stage) stage")
    }

    func testThereIsAtLeastOneNote() {
        // Not "one of each kind", which is what this asserted until 0.5.1
        // turned out to be all features and no fixes. A release is allowed to
        // be entirely one or the other; what it may not be is silent.
        XCTAssertFalse(Release.notes.isEmpty)
        for note in Release.notes {
            XCTAssertFalse(note.kind.symbol.isEmpty)
        }
    }

    func testEveryNoteIsWrittenInBothLanguages() {
        for note in Release.notes {
            let english = note.text(.english)
            let french = note.text(.french)
            XCTAssertFalse(english.isEmpty, "note \(note.id) has no English text")
            XCTAssertFalse(french.isEmpty, "note \(note.id) has no French text")
            XCTAssertNotEqual(english, french, "note \(note.id) was never translated")
        }
    }

    func testTheNotesUseTheApostropheTheAppItselfRecommends() {
        // Corrector converts U+0027 to U+2019 in French text. Showing the
        // straight one in its own release notes meant the app would have
        // flagged its own interface — which is exactly what the screenshot
        // showed.
        for note in Release.notes {
            for locale in [UILocale.english, .french] {
                XCTAssertFalse(note.text(locale).contains("\u{0027}"),
                               "note \(note.id) (\(locale)) uses a straight apostrophe")
            }
        }
    }

    func testNoteIdentifiersAreUnique() {
        // They drive a ForEach; duplicates silently drop rows.
        XCTAssertEqual(Set(Release.notes.map(\.id)).count, Release.notes.count)
    }

    func testEveryNoteKindHasASymbol() {
        for kind in [Release.Change.feature, .fix] {
            XCTAssertFalse(kind.symbol.isEmpty)
        }
    }
}
