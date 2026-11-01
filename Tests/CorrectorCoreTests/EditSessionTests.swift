import XCTest
import CorrectorDelta
@testable import CorrectorCore

final class EditSessionTests: XCTestCase {

    func testApplyDeltaBumpsRevisionAndText() {
        let session = InMemoryEditSession(text: "Hello")
        var edit = Delta(); edit.retain(5); edit.insert(" world")
        let state = try! session.applyDelta(edit)
        XCTAssertEqual(state.text, "Hello world")
        XCTAssertEqual(state.revision, 1)
    }

    func testInsertTextReplacesRange() {
        let session = InMemoryEditSession(text: "teh cat")
        _ = try! session.insertText("the", at: Selection(begin: 0, end: 3))
        XCTAssertEqual(session.text, "the cat")
    }

    func testInsertTextRejectsOutOfBoundsRange() {
        let session = InMemoryEditSession(text: "short")
        XCTAssertThrowsError(try session.insertText("x", at: Selection(begin: 0, end: 99))) {
            XCTAssertEqual($0 as? EditSessionError, .rangeOutOfBounds)
        }
    }

    func testCaretFollowsEditsMadeBeforeIt() {
        let session = InMemoryEditSession(text: "Hello world")
        try! session.setSelection(Selection(begin: 6, end: 6))
        var edit = Delta(); edit.insert("Oh, ")
        _ = try! session.applyDelta(edit)
        XCTAssertEqual(session.selection.begin, 10)
    }

    func testReadOnlySessionRefusesMutation() {
        let session = InMemoryEditSession(text: "fixed", capabilities: .readOnly)
        var edit = Delta(); edit.insert("x")
        XCTAssertThrowsError(try session.applyDelta(edit)) {
            XCTAssertEqual($0 as? EditSessionError, .unsupported(.replaceRange))
        }
    }

    func testCapabilitiesAreQueryable() {
        // Asking what a surface supports before offering an action is what
        // keeps an unsupported edit an error instead of a silent no-op.
        let editable = InMemoryEditSession(capabilities: .plainEditable)
        XCTAssertTrue(editable.capabilities.contains(.replaceRange))
        XCTAssertFalse(editable.capabilities.contains(.richText))
    }

    func testCopyTextUsesUTF16Offsets() {
        let session = InMemoryEditSession(text: "ab🎉cd")
        XCTAssertEqual(try session.copyText(range: Selection(begin: 4, end: 6)), "cd")
    }

    func testChangesSinceComposesHistory() {
        let session = InMemoryEditSession(text: "abc")
        let start = session.revision

        var one = Delta(); one.insert("X")
        _ = try! session.applyDelta(one)
        var two = Delta(); two.retain(4); two.insert("Y")
        _ = try! session.applyDelta(two)

        let combined = session.changesSince(revision: start)
        XCTAssertEqual(Delta(text: "abc").compose(combined).text, session.text)
        XCTAssertEqual(session.text, "XabcY")
    }

    func testChangesSinceCurrentRevisionIsEmpty() {
        let session = InMemoryEditSession(text: "abc")
        XCTAssertTrue(session.changesSince(revision: session.revision).isEmpty)
    }
}
