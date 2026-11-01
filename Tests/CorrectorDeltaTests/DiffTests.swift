import XCTest
@testable import CorrectorDelta

final class DiffTests: XCTestCase {

    private func roundTrip(_ strategy: DiffStrategy, _ old: String, _ new: String,
                           file: StaticString = #filePath, line: UInt = #line) {
        let delta = strategy.diff(from: old, to: new)
        XCTAssertEqual(Delta(text: old).compose(delta).text, new,
                       "diff did not reproduce the target", file: file, line: line)
    }

    func testAffixDiffRoundTrips() {
        let strategy = AffixDiffStrategy()
        roundTrip(strategy, "", "hello")
        roundTrip(strategy, "hello", "")
        roundTrip(strategy, "hello world", "hello brave world")
        roundTrip(strategy, "teh cat sat", "the cat sat")
        roundTrip(strategy, "abc", "xyz")
        roundTrip(strategy, "same", "same")
    }

    func testAffixDiffIsMinimal() {
        let delta = AffixDiffStrategy().diff(from: "the cat sat", to: "the bat sat")
        // Canonical form puts the insert before the adjacent delete, so that
        // two spellings of the same edit compare equal.
        XCTAssertEqual(delta.ops, [.retain(4), .insert("b"), .delete(1)])
    }

    func testWordDiffRoundTrips() {
        let strategy = WordLCSDiffStrategy()
        roundTrip(strategy, "the quick brown fox", "the slow brown fox")
        roundTrip(strategy, "one two three", "one three")
        roundTrip(strategy, "a b c d", "a x b y c d")
        roundTrip(strategy, "hello", "hello world")
        roundTrip(strategy, "", "new text")
    }

    func testWordDiffPreservesUnchangedWords() {
        let delta = WordLCSDiffStrategy().diff(from: "the quick brown fox",
                                               to: "the quick red fox")
        // "brown" is replaced; "the quick " and " fox" are retained.
        XCTAssertEqual(Delta(text: "the quick brown fox").compose(delta).text,
                       "the quick red fox")
        XCTAssertTrue(delta.ops.contains { $0.isRetain })
    }

    func testDiffHandlesEmoji() {
        let strategy = WordLCSDiffStrategy()
        roundTrip(strategy, "ship it 🎉", "ship it now 🎉")
        roundTrip(strategy, "a 🎉 b", "a b")
    }

    func testTokenizerIsLossless() {
        for sample in ["one two", "  leading", "trailing  ", "a\n\nb", ""] {
            XCTAssertEqual(WordLCSDiffStrategy.tokenize(sample).joined(), sample)
        }
    }
}
