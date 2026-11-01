import Foundation
import CorrectorCore
import CorrectorDelta

/// Terminal rendering of the model.
///
/// The same model the app draws, rendered as text. A second renderer keeps the
/// model honest: anything the engine cannot express without a window shows up
/// here as something that cannot be printed.
enum Render {
    static var useColor = ProcessInfo.processInfo.environment["NO_COLOR"] == nil
                       && isatty(fileno(stdout)) == 1

    static func paint(_ s: String, _ color: Theme.Color, underline: Bool = false) -> String {
        guard useColor else { return s }
        return underline ? color.underline(s) : color.fg(s)
    }

    static func dim(_ s: String) -> String {
        useColor ? "\u{1B}[2m\(s)\u{1B}[0m": s
    }

    static func bold(_ s: String) -> String {
        useColor ? "\u{1B}[1m\(s)\u{1B}[0m": s
    }

    // MARK: - Underlined document

    /// The document with each alert's highlight span underlined in its
    /// outcome colour — the terminal stand-in for the overlay decorations.
    /// The selected alert uses the active colour, the rest the inactive one.
    static func document(_ text: String, alerts: [Alert], selected: Int?) -> String {
        let spans = alerts
            .map { (begin: $0.highlightBegin, end: $0.highlightEnd,
                    outcome: $0.cardLayout.outcome, active: $0.id == selected) }
                        .sorted { $0.begin < $1.begin }

        var out = ""
        var cursor = 0
        for span in spans {
            guard span.begin >= cursor, span.end <= text.utf16Length,
                  span.end > span.begin else { continue }
            out += text.utf16Slice(cursor, span.begin)
            let piece = text.utf16Slice(span.begin, span.end)
            let color = Theme.UnderlineTokens.color(for: span.outcome, active: span.active)
            out += paint(piece, color, underline: true)
            cursor = span.end
        }
        out += text.utf16Slice(cursor, text.utf16Length)
        return out
    }

    // MARK: - Cards

    /// Compact card: title plus the primary replacement.
    /// Counterpart of `MiniAlertCardViewModel`.
    static func miniCard(_ alert: Alert, index: Int, strings: CLIStrings) -> String {
        let color = Theme.FillTokens.color(for: alert.cardLayout.outcome)
        let badge = paint("\(alert.cardLayout.outcome.glyph)", color)
        let head = "\(dim(String(format: "%2d", index)))  \(badge) \(bold(alert.title))"
        let tail = alert.replacements.first.map { r -> String in
            let shown = r.isEmpty ? strings.deleteReplacement : r
            return "  \(dim("→")) \(paint(shown, color))"
        } ?? ""
        return head + tail + "  " + dim("[\(alert.rangeDescription)]")
    }

    /// Expanded card: explanation, examples, alternatives and the action row.
    /// Counterpart of `FullAlertCardViewModel`; the action row
    /// is driven by the `AlertActions` bitmask.
    static func fullCard(_ alert: Alert, strings: CLIStrings,
                         width: Int = 72) -> String {
        let color = Theme.FillTokens.color(for: alert.cardLayout.outcome)
        var lines: [String] = []
        let rule = String(repeating: "─", count: width)

        lines.append(dim("┌" + rule + "┐"))
        lines.append("  " + paint(alert.cardLayout.outcome.glyph + " "
                                  + strings.outcome(alert.cardLayout.outcome).uppercased(), color)
                     + "   " + dim(alert.pname.rawValue))
        lines.append("  " + bold(alert.title))
        if !alert.details.isEmpty { lines.append("  " + alert.details) }

        if !alert.highlightText.isEmpty {
            lines.append("")
            lines.append("  " + dim("text:  ") + paint(alert.highlightText, color, underline: true))
        }
        if let first = alert.replacements.first {
            lines.append("  " + dim("fix:   ") + paint(first.isEmpty ? strings.deleteReplacement : first, color))
        }
        if alert.replacements.count > 1 {
            let others = alert.replacements.dropFirst()
                .map { $0.isEmpty ? strings.deleteReplacement : $0 }.joined(separator: ", ")
            lines.append("  " + dim("also:  ") + others)
        }
        if !alert.explanation.isEmpty {
            lines.append("")
            for line in wrap(alert.explanation, width: width - 4) {
                lines.append("  " + dim(line))
            }
        }
        for example in alert.examples {
            lines.append("  " + dim("e.g. " + example))
        }
        lines.append("")
        lines.append("  " + alert.actions.labels.map { dim("[\($0)]") }.joined(separator: " "))
        lines.append(dim("└" + rule + "┘"))
        return lines.joined(separator: "\n")
    }

    // MARK: - Summary panels

    static func scorePanel(_ scores: Scores, counts: [CardLayout.Outcome: Int],
                           strings: CLIStrings) -> String {
        var lines: [String] = []
        lines.append(bold(strings.score + "  ") + scoreBar(scores.generalScore) + "  "
                     + bold("\(scores.generalScore)") + dim("/100")
                     + "   " + dim("\(strings.tone): \(strings.toneName(scores.tone))"))
        lines.append("")
        for outcome in CardLayout.Outcome.allCases.sorted(by: { $0.priority < $1.priority }) {
            let value: Int
            switch outcome {
            case.correctness: value = scores.correctness
            case.clarity:     value = scores.clarity
            case.engagement:  value = scores.engagement
            case.styleGuide:  value = scores.styleGuide
            default: continue
            }
            let color = Theme.FillTokens.color(for: outcome)
            let count = counts[outcome] ?? 0
            lines.append("  " + paint(outcome.glyph, color) + " "
                         + strings.outcome(outcome)
                            .padding(toLength: 13, withPad: " ", startingAt: 0)
                         + scoreBar(value) + " " + String(format: "%3d", value)
                         + "   " + dim(strings.issueCount(count)))
        }
        return lines.joined(separator: "\n")
    }

    static func statsPanel(_ stats: TextStats, strings: CLIStrings) -> String {
        func pct(_ v: Int) -> String { dim("(\(ordinal(v)) \(strings.percentile))") }
        func label(_ s: String) -> String { s.padding(toLength: 17, withPad: " ", startingAt: 0) }
        return [
            "  \(bold(String(stats.words))) \(strings.words)   "
          + "\(bold(String(stats.sentences))) \(strings.sentences)   "
          + "\(bold(String(stats.chars))) \(strings.characters)",
            "  " + label(strings.uniqueWords)    + "\(stats.uniqueWords) \(pct(stats.uniqueWordsIndex))",
            "  " + label(strings.rareWords)      + "\(stats.rareWords) \(pct(stats.rareWordsIndex))",
            "  " + label(strings.wordLength)     + "\(stats.wordLength) \(pct(stats.wordLengthIndex))",
            "  " + label(strings.sentenceLength) + "\(stats.sentenceLength) \(pct(stats.sentenceLengthIndex))",
            "  " + label(strings.readability)    + "\(bold(String(stats.readabilityScore))) — "
          + strings.readabilityLabel(stats.readabilityScore),
            "  \(strings.reading) \(time(stats.readingTime))   "
          + "\(strings.speaking) \(time(stats.speakingTime))",
        ].joined(separator: "\n")
    }

    /// English ordinal suffix — "1st", "2nd", "3rd", "11th", "83rd".
    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    static func time(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s": "\(seconds / 60)m \(seconds % 60)s"
    }

    static func scoreBar(_ value: Int, width: Int = 20) -> String {
        let filled = max(0, min(width, Int((Double(value) / 100.0 * Double(width)).rounded())))
        let color: Theme.Color = value >= 80 ? Theme.Palette.teal : value >= 60 ? Theme.Palette.amber : Theme.Palette.rose
        return paint(String(repeating: "█", count: filled), color)
             + dim(String(repeating: "░", count: width - filled))
    }

    static func wrap(_ text: String, width: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            if current.isEmpty { current = String(word) }
            else if current.count + 1 + word.count <= width { current += " " + word }
            else { lines.append(current); current = String(word) }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
