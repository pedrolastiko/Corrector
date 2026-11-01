import XCTest
@testable import CorrectorCore

final class TokenizerTests: XCTestCase {

    func testWordOffsetsAreUTF16() {
        let tokens = Tokenizer.words(in: "hi 🎉 there")
        XCTAssertEqual(tokens.map(\.text), ["hi", "there"])
        // "hi " = 3, 🎉 = 2 units, " " = 1 →  "there" starts at 6.
        XCTAssertEqual(tokens.last?.begin, 6)
        XCTAssertEqual(tokens.last?.end, 11)
    }

    func testContractionsAndHyphensStayWhole() {
        XCTAssertEqual(Tokenizer.words(in: "don't re-open").map(\.text),
                       ["don't", "re-open"])
    }

    func testTrailingApostropheIsTrimmed() {
        XCTAssertEqual(Tokenizer.words(in: "'quoted'").map(\.text), ["quoted"])
    }

    func testSentenceSplittingOnTerminators() {
        let spans = Tokenizer.sentences(in: "One. Two! Three?")
        XCTAssertEqual(spans.count, 3)
    }

    func testSentenceSplittingOnBlankLine() {
        let text = "A heading\n\nThe body starts here."
        let spans = Tokenizer.sentences(in: text)
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(text.utf16Slice(spans[0].begin, spans[0].end), "A heading")
    }

    func testDecimalDoesNotSplitSentence() {
        XCTAssertEqual(Tokenizer.sentences(in: "It costs 3.50 today.").count, 1)
    }

    func testEllipsisCountsAsOneBoundary() {
        XCTAssertEqual(Tokenizer.sentences(in: "Wait... then go.").count, 2)
    }
}

final class TextStatsTests: XCTestCase {

    func testEmptyTextYieldsEmptyStats() {
        XCTAssertEqual(TextStats.compute(for: "   ").words, 0)
    }

    func testWordAndSentenceCounts() {
        let stats = TextStats.compute(for: "The cat sat. The dog ran.")
        XCTAssertEqual(stats.words, 6)
        XCTAssertEqual(stats.sentences, 2)
    }

    func testCharacterCountIsUTF16() {
        XCTAssertEqual(TextStats.compute(for: "a🎉").chars, 3)
    }

    func testReadingAndSpeakingTimeDiffer() {
        // Two separate rates, by design.
        let text = String(repeating: "word ", count: 238)
        let stats = TextStats.compute(for: text)
        XCTAssertGreaterThan(stats.speakingTime, stats.readingTime)
        XCTAssertEqual(stats.readingTime, 60, accuracy: 2)
    }

    func testSimpleTextScoresMoreReadableThanComplexText() {
        let simple = TextStats.compute(for: "The cat sat on the mat. It was warm.")
        let complex = TextStats.compute(for:
            "Notwithstanding the aforementioned considerations, the institutional "
          + "ramifications of the proposed reorganisation remain indeterminate.")
        XCTAssertGreaterThan(simple.readabilityScore, complex.readabilityScore)
    }

    func testPercentileIsBoundedAndMonotonic() {
        XCTAssertEqual(TextStats.percentile(0, mid: 0, spread: 1), 50)
        XCTAssertGreaterThan(TextStats.percentile(5, mid: 0, spread: 1),
                             TextStats.percentile(1, mid: 0, spread: 1))
        XCTAssertLessThanOrEqual(TextStats.percentile(1000, mid: 0, spread: 1), 100)
        XCTAssertGreaterThanOrEqual(TextStats.percentile(-1000, mid: 0, spread: 1), 0)
    }
}

final class ScoresTests: XCTestCase {

    private func alert(_ outcome: CardLayout.Outcome) -> Alert {
        Alert(id: Int.random(in: 1...10_000), rev: 0, begin: 0, end: 1, title: "x",
              pname: .misspelled, cardLayout: CardLayout(outcome: outcome))
    }

    func testCleanTextScoresFull() {
        let scores = Scores.compute(alerts: [], wordCount: 100)
        XCTAssertEqual(scores.generalScore, 100)
        XCTAssertEqual(scores.status, .complete)
    }

    func testEmptyDocumentIsEmptyStatus() {
        XCTAssertEqual(Scores.compute(alerts: [], wordCount: 0).status, .empty)
    }

    func testMoreIssuesLowerTheScore() {
        let few = Scores.compute(alerts: [alert(.correctness)], wordCount: 100)
        let many = Scores.compute(alerts: (0..<10).map { _ in alert(.correctness) },
                                  wordCount: 100)
        XCTAssertGreaterThan(few.generalScore, many.generalScore)
    }

    func testCorrectnessWeighsMoreThanStyle() {
        let correctness = Scores.compute(alerts: (0..<5).map { _ in alert(.correctness) },
                                         wordCount: 100)
        let style = Scores.compute(alerts: (0..<5).map { _ in alert(.styleGuide) },
                                   wordCount: 100)
        XCTAssertLessThan(correctness.generalScore, style.generalScore)
    }

    func testScoresStayInRange() {
        let scores = Scores.compute(alerts: (0..<500).map { _ in alert(.correctness) },
                                    wordCount: 10)
        XCTAssertGreaterThanOrEqual(scores.generalScore, 0)
        XCTAssertLessThanOrEqual(scores.generalScore, 100)
    }
}

final class DocumentStoreTests: XCTestCase {

    private func makeStore() throws -> (DocumentStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("corrector-tests-\(UUID().uuidString)")
        return (try DocumentStore(root: root), root)
    }

    override func tearDown() { super.tearDown() }

    func testDocumentIDIsStableAndHexadecimal() {
        let a = DocumentID.derive(application: "Mail", window: "Compose", field: "body")
        let b = DocumentID.derive(application: "Mail", window: "Compose", field: "body")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.value.count, 64)
        XCTAssertTrue(a.value.allSatisfy { $0.isHexDigit })
    }

    func testDocumentIDDiffersPerField() {
        XCTAssertNotEqual(DocumentID.derive(application: "Mail", window: "A", field: "body"),
                          DocumentID.derive(application: "Mail", window: "B", field: "body"))
    }

    func testSaveAndLoadRoundTrip() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = DocumentID.derive(application: "app", window: "w", field: "f")
        try store.save(StoredDocument(documentID: id.value, text: "hello", revision: 3))
        let loaded = try store.load(id)
        XCTAssertEqual(loaded?.text, "hello")
        XCTAssertEqual(loaded?.revision, 3)
        XCTAssertNil(loaded?.lastSyncedRevision)
    }

    func testCheckpointRecordsSyncedRevision() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let id = DocumentID.derive(application: "app", window: "w", field: "f")
        try store.save(StoredDocument(documentID: id.value, text: "hi", revision: 7))
        try store.checkpoint(id, syncedRevision: 7)
        XCTAssertEqual(try store.load(id)?.lastSyncedRevision, 7)
    }

}
