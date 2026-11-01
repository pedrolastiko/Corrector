import XCTest
@testable import CorrectorDelta

final class DeltaTests: XCTestCase {

    // MARK: - Construction and normalisation

    func testPushMergesAdjacentOperations() {
        var delta = Delta()
        delta.insert("Hello")
        delta.insert(" world")
        delta.retain(3)
        delta.retain(2)
        delta.delete(1)
        delta.delete(4)
        XCTAssertEqual(delta.ops, [.insert("Hello world"), .retain(5), .delete(5)])
    }

    func testPushNormalisesDeleteThenInsert() {
        var delta = Delta()
        delta.delete(3)
        delta.insert("abc")
        // Normalised to insert-first so equal edits compare equal.
        XCTAssertEqual(delta.ops, [.insert("abc"), .delete(3)])
    }

    func testChopRemovesTrailingPlainRetain() {
        var delta = Delta()
        delta.insert("a")
        delta.retain(5)
        XCTAssertEqual(delta.chop().ops, [.insert("a")])
    }

    func testChopKeepsTrailingRetainWithAttributes() {
        var delta = Delta()
        delta.insert("a")
        delta.retain(5, ["bold": "true"])
        XCTAssertEqual(delta.chop().ops.count, 2)
    }

    func testLengthAndChangeLength() {
        var delta = Delta()
        delta.retain(4)
        delta.insert("xyz")
        delta.delete(2)
        XCTAssertEqual(delta.length, 9)
        XCTAssertEqual(delta.changeLength, 1)   // +3 inserted, -2 deleted
    }

    // MARK: - compose

    func testComposeInsertIntoDocument() {
        let document = Delta(text: "Hello world")
        var edit = Delta()
        edit.retain(5)
        edit.insert(",")
        XCTAssertEqual(document.compose(edit).text, "Hello, world")
    }

    func testComposeDeleteFromDocument() {
        let document = Delta(text: "Hello cruel world")
        var edit = Delta()
        edit.retain(6)
        edit.delete(6)
        XCTAssertEqual(document.compose(edit).text, "Hello world")
    }

    func testComposeReplacement() {
        let document = Delta(text: "teh cat")
        var edit = Delta()
        edit.delete(3)
        edit.insert("the")
        XCTAssertEqual(document.compose(edit).text, "the cat")
    }

    func testComposeIsAssociative() {
        let document = Delta(text: "abcdef")
        var first = Delta(); first.retain(1); first.insert("X")
        var second = Delta(); second.retain(4); second.delete(2)
        XCTAssertEqual(document.compose(first).compose(second).text,
                       document.compose(first.compose(second)).text)
    }

    func testComposeMergesAttributes() {
        var document = Delta(); document.insert("abc")
        var edit = Delta(); edit.retain(3, ["bold": "true"])
        let result = document.compose(edit)
        XCTAssertEqual(result.ops, [.insert("abc", ["bold": "true"])])
    }

    // MARK: - transform

    func testTransformConcurrentInserts() {
        // Two people insert at the same place; priority decides who goes first.
        var mine = Delta(); mine.insert("A")
        var theirs = Delta(); theirs.insert("B")

        let theirsRebased = mine.transform(theirs, priority: true)
        let document = Delta(text: "xy")
        XCTAssertEqual(document.compose(mine).compose(theirsRebased).text, "ABxy")

        let mineRebased = theirs.transform(mine, priority: false)
        XCTAssertEqual(document.compose(theirs).compose(mineRebased).text, "ABxy")
    }

    func testTransformConvergesForInsertAndDelete() {
        let document = Delta(text: "abcdef")
        var insertion = Delta(); insertion.retain(2); insertion.insert("X")
        var deletion = Delta(); deletion.retain(4); deletion.delete(2)

        let deletionRebased = insertion.transform(deletion, priority: true)
        let insertionRebased = deletion.transform(insertion, priority: false)

        XCTAssertEqual(document.compose(insertion).compose(deletionRebased).text,
                       document.compose(deletion).compose(insertionRebased).text)
        XCTAssertEqual(document.compose(insertion).compose(deletionRebased).text, "abXcd")
    }

    // MARK: - invert

    func testInvertUndoesInsert() {
        let document = Delta(text: "Hello")
        var edit = Delta(); edit.retain(5); edit.insert(" world")
        let applied = document.compose(edit)
        XCTAssertEqual(applied.compose(edit.invert(against: document)).text, "Hello")
    }

    func testInvertUndoesDelete() {
        let document = Delta(text: "Hello world")
        var edit = Delta(); edit.retain(5); edit.delete(6)
        let applied = document.compose(edit)
        XCTAssertEqual(applied.text, "Hello")
        XCTAssertEqual(applied.compose(edit.invert(against: document)).text, "Hello world")
    }

    func testInvertUndoesReplacement() {
        let document = Delta(text: "teh quick fox")
        var edit = Delta(); edit.delete(3); edit.insert("the")
        let applied = document.compose(edit)
        XCTAssertEqual(applied.compose(edit.invert(against: document)).text, "teh quick fox")
    }

    // MARK: - position transforms

    func testTransformPositionAfterInsertBefore() {
        var edit = Delta(); edit.insert("1234")
        XCTAssertEqual(edit.transformPosition(0, priority: false), 4)
        XCTAssertEqual(edit.transformPosition(7, priority: false), 11)
    }

    func testTransformPositionWithPriorityPinsAtInsertionPoint() {
        var edit = Delta(); edit.insert("1234")
        XCTAssertEqual(edit.transformPosition(0, priority: true), 0)
    }

    func testTransformPositionAfterDelete() {
        var edit = Delta(); edit.retain(2); edit.delete(3)
        XCTAssertEqual(edit.transformPosition(1), 1)   // before the cut
        XCTAssertEqual(edit.transformPosition(3), 2)   // inside the cut, clamps
        XCTAssertEqual(edit.transformPosition(8), 5)   // after the cut
    }

    func testTransformPositionIgnoresEditsAfterIt() {
        var edit = Delta(); edit.retain(10); edit.insert("zzz")
        XCTAssertEqual(edit.transformPosition(4), 4)
    }

    // MARK: - slice / eachLine

    func testSlice() {
        let document = Delta(text: "Hello world")
        XCTAssertEqual(document.slice(6, 11).text, "world")
        XCTAssertEqual(document.slice(0, 5).text, "Hello")
    }

    func testEachLine() {
        let document = Delta(text: "one\ntwo\nthree")
        var lines: [String] = []
        document.eachLine { line, _ in lines.append(line.text) }
        XCTAssertEqual(lines, ["one", "two", "three"])
    }

    // MARK: - UTF-16 behaviour

    func testLengthCountsUTF16CodeUnits() {
        // An emoji outside the BMP is two UTF-16 code units.
        XCTAssertEqual(Delta(text: "🎉").length, 2)
        XCTAssertEqual(Delta(text: "é").length, 1)
        XCTAssertEqual(Delta(text: "a🎉b").length, 4)
    }

    func testTransformPositionAcrossEmoji() {
        // "hi " = 3, 🎉 = 2 (surrogate pair), " " = 1, "there" = 5.
        let document = Delta(text: "hi 🎉 there")
        XCTAssertEqual(document.length, 11)
        var edit = Delta(); edit.insert("🎉")         // two code units at the front
        XCTAssertEqual(edit.transformPosition(3, priority: false), 5)
    }

    func testSliceAcrossEmoji() {
        let document = Delta(text: "ab🎉cd")
        // 🎉 occupies units 2..<4, so "cd" starts at 4.
        XCTAssertEqual(document.slice(4, 6).text, "cd")
    }
}
