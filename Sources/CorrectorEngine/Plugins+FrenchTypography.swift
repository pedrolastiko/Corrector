import Foundation
import CorrectorCore
import CorrectorDelta

/// French typographic spacing.
///
/// This is the rule that most clearly shows why the engine must branch on
/// language rather than parameterise: French *requires* a space before `;`
/// `!` `?` `:`, and the English punctuation plugin flags exactly that as an
/// error. The same input is correct in one language and wrong in the other.
///
/// The spaces are non-breaking so the mark can never begin a line:
/// U+202F (espace fine insécable) before `;` `!` `?`, U+00A0 (espace
/// insécable) before `:`.
public struct FrenchTypographyPlugin: CheckPlugin {
    public let identifier = "fr.spacing"
    public let feature: FeatureSet = .punctuation
    public let languages: Set<Language> = [.french]
    public init() {}

    private static let narrow: Set<Character> = [";", "!", "?"]
    private static let wide: Set<Character> = [":"]

    /// The forms that actually elide.
    ///
    /// Required, not decoration. Without it the rule below is "an apostrophe
    /// followed by a space is wrong", which is false in both languages: an
    /// English plural possessive ("the dogs' owners") and any closing single
    /// quote are exactly that shape. Matching the word in front, and demanding
    /// that it begin at a word boundary, is what separates « l' ami » — where
    /// the space is a typing slip — from « les chats' » where it is not.
    private static let elidable: Set<String> = [
        "c", "d", "j", "l", "m", "n", "s", "t", "qu",
        "jusqu", "lorsqu", "puisqu", "quoiqu", "presqu", "quelqu", "aujourd",
    ]

    /// « l' application » → « l'application ».
    ///
    /// The apostrophe of elision binds the two words into one; a space after
    /// it is never correct. The draft removes the spaces and leaves the
    /// apostrophe itself alone, so a straight `'` is still the typographic
    /// rule's business and stays mutable on its own.
    private func elisionSpacing(_ context: CheckContext) -> [AlertDraft] {
        let units = Array(context.text.utf16)
        func character(at index: Int) -> Character? {
            guard index >= 0, index < units.count,
                  let scalar = UnicodeScalar(units[index]) else { return nil }
            return Character(scalar)
        }

        var drafts: [AlertDraft] = []
        for index in 0..<units.count {
            guard let mark = character(at: index),
                  mark == "\u{0027}" || mark == "\u{2019}" else { continue }

            // Spaces to drop, and a word on the far side of them.
            var run = index + 1
            while run < units.count, character(at: run) == " " { run += 1 }
            guard run > index + 1,
                  let following = character(at: run), following.isLetter else { continue }

            // The elidable form in front, starting at a word boundary.
            var start = index
            while start > 0, let before = character(at: start - 1),
                  before.isLetter { start -= 1 }
            let word = String(decoding: units[start..<index], as: UTF16.self).lowercased()
            guard Self.elidable.contains(word) else { continue }

            let elided = String(decoding: units[start..<(index + 1)], as: UTF16.self)
            drafts.append(AlertDraft(
                begin: index + 1, end: run,
                highlightBegin: start, highlightEnd: min(units.count, run + 1),
                title: "Espace après l'apostrophe",
                details: "« \(elided) \(following)… » → « \(elided)\(following)… »",
                explanation: "L'apostrophe d'élision soude les deux mots: "
                           + "elle n'est jamais suivie d'une espace.",
                examples: ["l'application", "qu'il", "aujourd'hui"],
                pname: .spaceAfterApostrophe, outcome: .correctness,
                replacements: [""]))
        }
        return drafts
    }

    public func check(_ context: CheckContext) -> [AlertDraft] {
        var drafts = Spacing.collapsibleRuns(in: context)
        drafts.append(contentsOf: elisionSpacing(context))
        let units = Array(context.text.utf16)

        func character(at index: Int) -> Character? {
            guard index >= 0, index < units.count,
                  let scalar = UnicodeScalar(units[index]) else { return nil }
            return Character(scalar)
        }

        var index = 0
        while index < units.count {
            guard let mark = character(at: index) else { index += 1; continue }
            let isNarrow = Self.narrow.contains(mark)
            let isWide = Self.wide.contains(mark)
            guard isNarrow || isWide else { index += 1; continue }

            // Only the first mark of a run ("!!!" takes one space, not three).
            if let previous = character(at: index - 1),
               Self.narrow.contains(previous) || Self.wide.contains(previous) {
                index += 1
                continue
            }
            // Skip "14:30" and "https://" — a colon between digits or before a
            // slash is not punctuation in the typographic sense.
            if isWide {
                if let before = character(at: index - 1), before.isNumber,
                   let after = character(at: index + 1), after.isNumber {
                    index += 1; continue
                }
                if character(at: index + 1) == "/" { index += 1; continue }
            }

            let required = isNarrow ? Typography.narrowNoBreakSpace : Typography.noBreakSpace
            let label = isNarrow ? "espace fine insécable": "espace insécable"

            guard let previous = character(at: index - 1) else { index += 1; continue }

            if Typography.isNonBreakingSpace(previous) {
                // Already non-breaking — but check it is the right width.
                if String(previous) != required {
                    drafts.append(AlertDraft(
                        begin: index - 1, end: index,
                        highlightBegin: max(0, index - 1), highlightEnd: index + 1,
                        title: "Espace incorrecte avant « \(mark) »",
                        details: "Utilisez une \(label).",
                        explanation: "En typographie française, « \(mark) » est précédé "
                                   + "d'une \(label).",
                        pname: .frenchSpacing, outcome: .styleGuide,
                        replacements: [required]))
                }
            } else if previous == " " {
                // A breaking space: the mark could end up alone on a new line.
                //
                // The whole run goes, not just the last one. « mot  ! » typed
                // with two spaces has to come back as « mot ! » in one accept;
                // replacing only the final space would leave an ordinary one
                // in front of the mark, which is the error we started from.
                var start = index - 1
                while start > 0, character(at: start - 1) == " " { start -= 1 }
                let extra = index - start > 1
                drafts.append(AlertDraft(
                    begin: start, end: index,
                    highlightBegin: max(0, start), highlightEnd: index + 1,
                    title: extra
                        ? "Espaces multiples avant « \(mark) »"
                        : "Espace sécable avant « \(mark) »",
                    details: "Remplacez par une \(label).",
                    explanation: "Une espace ordinaire autorise un retour à la ligne "
                               + "qui laisserait « \(mark) » seul en début de ligne.",
                    pname: .frenchSpacing, outcome: .styleGuide,
                    replacements: [required]))
            } else if !previous.isWhitespace {
                drafts.append(AlertDraft(
                    begin: index, end: index,
                    highlightBegin: max(0, index - 1), highlightEnd: index + 1,
                    title: "Espace manquante avant « \(mark) »",
                    details: "Insérez une \(label).",
                    explanation: "En typographie française, « \(mark) » est précédé "
                               + "d'une \(label).",
                    pname: .frenchSpacing, outcome: .styleGuide,
                    replacements: [required]))
            }
            index += 1
        }
        return drafts
    }
}

/// French marks: guillemets, the typographic apostrophe, and « etc. ».
///
/// Split from the spacing rules because these are house-style choices a user
/// toggles under "style guide", whereas a missing space before `?` belongs
/// with punctuation. Same outcome on the card, different switch.
public struct FrenchMarksPlugin: CheckPlugin {
    public let identifier = "fr.marks"
    public let feature: FeatureSet = .styleGuide
    public let languages: Set<Language> = [.french]
    public init() {}

    public func check(_ context: CheckContext) -> [AlertDraft] {
        var drafts = guillemets(context)
        drafts.append(contentsOf: apostrophes(context))
        drafts.append(contentsOf: etcetera(context))
        return drafts
    }

    /// Straight quotes should be guillemets, with inner non-breaking spaces.
    private func guillemets(_ context: CheckContext) -> [AlertDraft] {
        let units = Array(context.text.utf16)
        func character(at index: Int) -> Character? {
            guard index >= 0, index < units.count,
                  let scalar = UnicodeScalar(units[index]) else { return nil }
            return Character(scalar)
        }

        var drafts: [AlertDraft] = []
        for index in 0..<units.count {
            guard character(at: index) == "\"" else { continue }

            // Opening or closing is decided from the surrounding characters,
            // not from a running count of quotes seen so far. A counter breaks
            // as soon as one quote has been converted: the remaining straight
            // quote becomes "the first" on the next pass and is reopened.
            let previous = character(at: index - 1)
            let next = character(at: index + 1)
            let followsContent = previous.map {
                !$0.isWhitespace && !Typography.isNonBreakingSpace($0) && $0 != "\u{00AB}"
            } ?? false
            let precedesContent = next.map { !$0.isWhitespace } ?? false
            let isOpening = !followsContent && precedesContent

            drafts.append(AlertDraft(
                begin: index, end: index + 1,
                title: isOpening ? "Guillemet ouvrant": "Guillemet fermant",
                details: "Utilisez « … ».",
                explanation: "Le français emploie les guillemets chevrons, "
                           + "avec une espace insécable à l'intérieur.",
                examples: ["« comme ceci »"],
                pname: .frenchQuotes, outcome: .styleGuide,
                replacements: [isOpening
                    ? "\u{00AB}\(Typography.noBreakSpace)"
: "\(Typography.noBreakSpace)\u{00BB}"]))
        }
        return drafts
    }

    /// The typewriter apostrophe should be the typographic one.
    private func apostrophes(_ context: CheckContext) -> [AlertDraft] {
        var drafts: [AlertDraft] = []
        let units = Array(context.text.utf16)
        let straight = UInt16(39)   // '
        for index in 0..<units.count where units[index] == straight {
            // Only between letters, i.e. a genuine elision rather than a quote.
            guard index > 0, index + 1 < units.count,
                  let beforeScalar = UnicodeScalar(units[index - 1]),
                  let afterScalar = UnicodeScalar(units[index + 1]),
                  Character(beforeScalar).isLetter,
                  Character(afterScalar).isLetter else { continue }
            drafts.append(AlertDraft(
                begin: index, end: index + 1,
                highlightBegin: max(0, index - 1), highlightEnd: index + 2,
                title: "Apostrophe typographique",
                details: "Utilisez ’ plutôt que '.",
                explanation: "L'apostrophe courbe est la forme typographique correcte.",
                pname: .typographicApostrophe, outcome: .styleGuide,
                replacements: [Typography.rightSingleQuote]))
        }
        return drafts
    }

    /// « etc... » → « etc. »
    private func etcetera(_ context: CheckContext) -> [AlertDraft] {
        let lowered = context.text.lowercased()
        var drafts: [AlertDraft] = []
        var searchStart = lowered.startIndex
        while let range = lowered.range(of: "etc...", range: searchStart..<lowered.endIndex) {
            let begin = lowered.utf16.distance(
                from: lowered.utf16.startIndex,
                to: range.lowerBound.samePosition(in: lowered.utf16)!)
            drafts.append(AlertDraft(
                begin: begin, end: begin + 6,
                title: "« etc. » ne prend qu'un point",
                details: "« etc... » → « etc. »",
                explanation: "« Etc. » est une abréviation: son point final suffit, "
                           + "et ne se cumule pas avec des points de suspension.",
                pname: .etcEllipsis, outcome: .styleGuide,
                replacements: ["etc."]))
            searchStart = range.upperBound
        }
        return drafts
    }
}
