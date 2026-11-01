import SwiftUI
import CorrectorCore
import CorrectorAppCore

/// Overall score plus a per-category breakdown.
///
/// The summary a reader wants before the list itself: one overall number, then
/// the per-category counts that explain it.
struct ScoreView: View {
    let scores: Scores
    let counts: [CardLayout.Outcome: Int]
    let strings: Strings

    private var tint: Color {
        switch scores.generalScore {
        case 80...: return Theme.Palette.teal.swiftUIColor
        case 60..<80: return Theme.Palette.amber.swiftUIColor
        default: return Theme.Palette.rose.swiftUIColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.lg) {
            HStack(alignment: .firstTextBaseline, spacing: Metric.md) {
                Text("\(scores.generalScore)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                            .monospacedDigit()
                VStack(alignment: .leading, spacing: 0) {
                    Text(strings.overallScore).font(.subheadline).fontWeight(.medium)
                    Text("\(strings.tone): \(strings.toneName(scores.tone))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(spacing: Metric.sm + 2) {
                ForEach(Self.breakdown(scores), id: \.outcome) { row in
                    ScoreRow(outcome: row.outcome,
                             value: row.value,
                             count: counts[row.outcome] ?? 0,
                             label: strings.outcome(row.outcome))
                }
            }
        }
            .padding(Metric.lg)
                .background(.quaternary.opacity(0.4), in:
            RoundedRectangle(cornerRadius: Metric.radiusMedium))
    }

    private static func breakdown(_ s: Scores)
    -> [(outcome: CardLayout.Outcome, value: Int)] {
        [(.correctness, s.correctness), (.clarity, s.clarity),
         (.engagement, s.engagement), (.styleGuide, s.styleGuide)]
    }
}

private struct ScoreRow: View {
    /// Same thresholds as the command line, so the two agree.
    static func qualityTint(_ value: Int) -> Color {
        switch value {
        case 80...: return Theme.Palette.teal.swiftUIColor
        case 60..<80: return Theme.Palette.amber.swiftUIColor
        default: return Theme.Palette.rose.swiftUIColor
        }
    }

    let outcome: CardLayout.Outcome
    let value: Int
    let count: Int
    let label: String

    var body: some View {
        HStack(spacing: Metric.md) {
            Image(systemName: outcome.symbolName)
                .font(.caption)
                    .foregroundStyle(outcome.tint)
                        .frame(width: 14)
            Text(label)
                .font(.caption)
                    .frame(width: 78, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 5)
                    // Coloured by the score, not by the category: a category
                    // tint on the bar meant a perfect correctness score drew a
                    // red bar, which reads as failure. The icon keeps the
                    // category colour, so identity and quality stay separate.
                    Capsule().fill(ScoreRow.qualityTint(value))
                        .frame(width: geometry.size.width * CGFloat(value) / 100.0,
                               height: 5)
                }
                    .frame(height: geometry.size.height, alignment: .center)
            }
                .frame(height: 10)
            Text(count == 0 ? "—": "\(count)")
                .font(.caption2).monospacedDigit()
                    .foregroundStyle(count == 0 ? .secondary : outcome.tint)
                        .frame(width: 18, alignment: .trailing)
        }
    }
}

/// Readability and length statistics.
struct StatsView: View {
    let stats: TextStats
    let strings: Strings

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.sm) {
            row(strings.words, "\(stats.words)")
            row(strings.sentences, "\(stats.sentences)")
            row(strings.readability,
                "\(stats.readabilityScore) · \(strings.readabilityLabel(stats.readabilityScore))")
            // Two separate rates: people read faster than they speak.
            row(strings.readingTime, format(stats.readingTime))
            row(strings.speakingTime, format(stats.speakingTime))
        }
            .font(.caption)
                .padding(Metric.lg)
                    .background(.quaternary.opacity(0.4), in:
            RoundedRectangle(cornerRadius: Metric.radiusMedium))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    private func format(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s": "\(seconds / 60)m \(seconds % 60)s"
    }
}
