import Foundation

/// Per-dimension document scores, 0...100.
///
/// Every score is computed locally from the text and the alerts already in
/// front of the user — no model, no network — so the same document always
/// scores the same and a test can assert on the number.
public struct Scores: Equatable, Codable, Sendable {
    public var generalScore: Int
    public var correctness: Int
    public var clarity: Int
    public var engagement: Int
    public var styleGuide: Int
    public var tone: String
    public var status: Status

    public enum Status: String, Codable, Sendable {
        case empty, partial, complete
    }

    public init(generalScore: Int = 0, correctness: Int = 0, clarity: Int = 0,
                engagement: Int = 0, styleGuide: Int = 0,
                tone: String = "neutral", status: Status = .empty) {
        self.generalScore = generalScore
        self.correctness = correctness
        self.clarity = clarity
        self.engagement = engagement
        self.styleGuide = styleGuide
        self.tone = tone
        self.status = status
    }

    public static let empty = Scores()

    /// Score a document from its alerts and word count.
    ///
    /// Each dimension starts at 100 and loses ground as alerts accumulate,
    /// normalised per 100 words so a long document is not punished for length.
    /// The curve is deliberately gentle: a single issue should not look fatal.
    public static func compute(alerts: [Alert], wordCount: Int) -> Scores {
        guard wordCount > 0 else { return .empty }
        let per100 = Double(wordCount) / 100.0

        func dimension(_ outcome: CardLayout.Outcome, weight: Double) -> Int {
            let hits = alerts.filter { !$0.muted && $0.cardLayout.outcome == outcome }.count
            let density = Double(hits) / max(per100, 0.3)
            let penalty = 100.0 * (1.0 - exp(-density * weight))
            return max(0, min(100, Int((100.0 - penalty).rounded())))
        }

        let correctness = dimension(.correctness, weight: 0.30)
        let clarity     = dimension(.clarity,     weight: 0.22)
        let engagement  = dimension(.engagement,  weight: 0.16)
        let styleGuide  = dimension(.styleGuide,  weight: 0.12)

        // Correctness dominates: a reader forgives a dull sentence sooner than
        // a misspelling.
        let general = Int((Double(correctness) * 0.45
                         + Double(clarity)     * 0.25
                         + Double(engagement)  * 0.18
                         + Double(styleGuide)  * 0.12).rounded())

        return Scores(generalScore: general, correctness: correctness, clarity: clarity,
                      engagement: engagement, styleGuide: styleGuide,
                      tone: tone(for: alerts), status: .complete)
    }

    private static func tone(for alerts: [Alert]) -> String {
        if alerts.contains(where: { $0.pname == .passiveVoice }) { return "detached" }
        if alerts.contains(where: { $0.pname == .weakIntensifier }) { return "tentative" }
        if alerts.contains(where: { $0.pname == .fillerWord }) { return "informal" }
        return "neutral"
    }
}
