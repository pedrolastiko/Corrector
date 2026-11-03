import Foundation
import CorrectorCore

/// Runs of ordinary spaces between words — the one spacing rule both languages
/// share.
///
/// It lives here, and not in either punctuation plugin, because of a mistake
/// worth naming. `PunctuationPlugin` is English-only for a good reason: it
/// flags a space before `!`, which French *requires*. But collapsing a run of
/// spaces was never English-specific, and sitting inside that plugin it
/// inherited the restriction by accident. French documents went unchecked for
/// double spaces entirely. A shared function rather than a shared plugin keeps
/// `CheckPlugin.languages` meaning exactly one thing: every registered plugin
/// still belongs to a single language.
enum Spacing {

    /// Which marks French puts a non-breaking space in front of.
    ///
    /// A run of spaces before one of these is not collapsed here, because the
    /// right answer is not "one space" — it is a narrow or wide non-breaking
    /// space, and `FrenchTypographyPlugin` is the rule that knows which. It
    /// replaces the whole run, so a single accept leaves « mot ! » correct
    /// rather than « mot !» with a stray space still in front of the mark.
    private static let frenchDoublePunctuation: Set<Character> = [";", "!", "?", ":"]

    /// One draft per run of two or more spaces.
    ///
    /// Only U+0020 counts. A non-breaking space is a character someone chose
    /// on purpose, and a tab or a newline is layout rather than a typing slip.
    static func collapsibleRuns(in context: CheckContext) -> [AlertDraft] {
        let units = Array(context.text.utf16)
        let space = UInt16(32)

        var drafts: [AlertDraft] = []
        var index = 0
        while index < units.count {
            guard units[index] == space else { index += 1; continue }

            let start = index
            var run = index
            while run < units.count, units[run] == space { run += 1 }
            index = run                       // past the whole run, either way

            let length = run - start
            guard length >= 2 else { continue }

            if context.language == .french, run < units.count,
               let scalar = UnicodeScalar(units[run]),
               frenchDoublePunctuation.contains(Character(scalar)) {
                continue
            }

            drafts.append(AlertDraft(
                begin: start, end: run,
                title: context.language == .french
                    ? "Espaces multiples"
                    : "Extra space",
                details: context.language == .french
                    ? "Remplacez \(length) espaces par une seule."
                    : "Collapse \(length) spaces to one.",
                explanation: context.language == .french
                    ? "Une seule espace sépare deux mots, y compris après un point."
                    : "Modern typesetting uses a single space between sentences.",
                pname: .doubleSpace, outcome: .correctness,
                replacements: [" "]))
        }
        return drafts
    }
}
