import Foundation
import CorrectorDelta

/// Readability and length statistics for a document.
///
/// Each `*Index` field is a **percentile rank** paired with the raw metric it
/// ranks: a readability number on its own says nothing without what it is
/// being compared against. Reading and speaking time are measured separately
/// rather than one being the other times a constant — people read faster than
/// they speak, by a ratio that is not fixed.
public struct TextStats: Equatable, Codable, Sendable {
    public var chars: Int
    public var words: Int
    public var sentences: Int
    public var uniqueWords: Int
    public var rareWords: Int

    public var wordLength: Double
    public var sentenceLength: Double

    /// Percentile ranks, 0...100.
    public var uniqueWordsIndex: Int
    public var rareWordsIndex: Int
    public var wordLengthIndex: Int
    public var sentenceLengthIndex: Int

    public var readabilityScore: Int
    public var readabilityDescription: String

    /// Seconds.
    public var readingTime: Int
    public var speakingTime: Int

    public static let empty = TextStats(
        chars: 0, words: 0, sentences: 0, uniqueWords: 0, rareWords: 0,
        wordLength: 0, sentenceLength: 0,
        uniqueWordsIndex: 0, rareWordsIndex: 0, wordLengthIndex: 0, sentenceLengthIndex: 0,
        readabilityScore: 0, readabilityDescription: "No text",
        readingTime: 0, speakingTime: 0)

    /// Words per minute used for the two time estimates.
    ///
    /// Published averages for silent reading and for speaking aloud. They are
    /// constants rather than measurements, so the estimate is a rough guide —
    /// which is all a reading time ever is.
    public static let readingWPM = 238.0
    public static let speakingWPM = 150.0

    public static func compute(for text: String,
                               language: Language = .english) -> TextStats {
        let tokens = Tokenizer.words(in: text, language: language)
        guard !tokens.isEmpty else { return .empty }

        let sentenceSpans = Tokenizer.sentences(in: text)
        let words = tokens.count
        let sentences = max(1, sentenceSpans.count)
        let lowered = tokens.map { $0.text.lowercased() }
        let unique = Set(lowered).count
        let common = Tokenizer.commonWords(for: language)
        let rare = lowered.filter { !common.contains($0) }.count

        let avgWordLength = Double(lowered.reduce(0) { $0 + $1.count }) / Double(words)
        let avgSentenceLength = Double(words) / Double(sentences)

        let syllables = lowered.reduce(0) {
            $0 + Tokenizer.syllableCount($1, language: language)
        }
        // Flesch for English; Kandel & Moles' French adaptation of it, which
        // retunes the constants for French's longer words and syllable count.
        let perWord = Double(syllables) / Double(words)
        let raw: Double
        switch language {
        case.english: raw = 206.835 - 1.015 * avgSentenceLength - 84.6 * perWord
        case.french:  raw = 207.0   - 1.015 * avgSentenceLength - 73.6 * perWord
        }
        let readability = max(0, min(100, Int(raw.rounded())))

        return TextStats(
            chars: text.utf16Length,
            words: words,
            sentences: sentences,
            uniqueWords: unique,
            rareWords: rare,
            wordLength: (avgWordLength * 10).rounded() / 10,
            sentenceLength: (avgSentenceLength * 10).rounded() / 10,
            uniqueWordsIndex: percentile(Double(unique) / Double(words), mid: 0.55, spread: 0.18),
            rareWordsIndex: percentile(Double(rare) / Double(words), mid: 0.30, spread: 0.15),
            wordLengthIndex: percentile(avgWordLength, mid: 4.7, spread: 1.0),
            sentenceLengthIndex: percentile(avgSentenceLength, mid: 17.0, spread: 7.0),
            readabilityScore: readability,
            readabilityDescription: describe(readability),
            readingTime: Int((Double(words) / readingWPM * 60).rounded()),
            speakingTime: Int((Double(words) / speakingWPM * 60).rounded()))
    }

    /// Map a raw metric onto a 0...100 percentile using a logistic curve
    /// centred on `mid`. A curve rather than a corpus comparison: it needs no
    /// reference data, it is monotonic, and it never returns 0 or 100 — a
    /// document is never perfectly readable or perfectly unreadable.
    static func percentile(_ value: Double, mid: Double, spread: Double) -> Int {
        guard spread > 0 else { return 50 }
        let z = (value - mid) / spread
        return max(0, min(100, Int((100.0 / (1.0 + exp(-z))).rounded())))
    }

    public static func describe(_ score: Int) -> String {
        switch score {
        case 90...: return "Very easy to read"
        case 70..<90: return "Easy to read"
        case 60..<70: return "Plain English"
        case 50..<60: return "Fairly difficult"
        case 30..<50: return "Difficult"
        default: return "Very difficult"
        }
    }
}
