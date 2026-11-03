import Foundation
import CorrectorCore
import CorrectorDelta

// MARK: - Spelling

/// Dictionary-driven spelling and repeated-word detection.
///
/// Uses a curated misspelling table rather than the system spell checker, so
/// results are deterministic and the test suite can assert on them. The system
/// checker is consulted separately, through `SpellDictionary`, where breadth
/// matters more than reproducibility.
public struct SpellingPlugin: CheckPlugin {
    public let identifier = "spelling"
    public let feature: FeatureSet = .spelling
    public let languages: Set<Language> = [.english]

    /// Where spelling knowledge comes from. Injected so the engine can be
    /// deterministic under test and knowledgeable in production.
    let dictionary: SpellDictionary

    public init(dictionary: SpellDictionary = TableSpellDictionary.standard) {
        self.dictionary = dictionary
    }

    /// Corrector's own correction table.
    public static let corrections: [String: String] = [
        "teh": "the", "recieve": "receive", "recieved": "received",
        "seperate": "separate", "seperated": "separated", "definately": "definitely",
        "occured": "occurred", "occurence": "occurrence", "neccessary": "necessary",
        "accomodate": "accommodate", "acheive": "achieve", "adress": "address",
        "arguement": "argument", "basicly": "basically", "beleive": "believe",
        "calender": "calendar", "collegue": "colleague", "comming": "coming",
        "commited": "committed", "concious": "conscious", "dissapoint": "disappoint",
        "embarass": "embarrass", "enviroment": "environment", "existance": "existence",
        "familar": "familiar", "finaly": "finally", "foriegn": "foreign",
        "goverment": "government", "grammer": "grammar", "happend": "happened",
        "independant": "independent", "intrest": "interest", "knowlege": "knowledge",
        "liason": "liaison", "maintainance": "maintenance", "managment": "management",
        "millenium": "millennium", "noticable": "noticeable", "occassion": "occasion",
        "perseverence": "perseverance", "personell": "personnel", "posession": "possession",
        "prefered": "preferred", "priviledge": "privilege", "pronounciation": "pronunciation",
        "publically": "publicly", "questionaire": "questionnaire", "refered": "referred",
        "relevent": "relevant", "rember": "remember", "resturant": "restaurant",
        "rythm": "rhythm", "sucessful": "successful", "supercede": "supersede",
        "surprize": "surprise", "tommorow": "tomorrow", "truely": "truly",
        "untill": "until", "writen": "written", "occuring": "occurring", "wierd": "weird", "writting": "writing", "alot": "a lot",
        "thier": "their", "wich": "which", "becuase": "because", "freind": "friend",
    ]

    public func check(_ context: CheckContext) -> [AlertDraft] {
        var drafts: [AlertDraft] = []

        for found in dictionary.misspellings(in: context.text,
                                             tokens: context.tokens,
                                             language: .english,
                                             dialect: context.dialect) {
            drafts.append(AlertDraft(
                begin: found.begin, end: found.end,
                title: "Misspelled word",
                details: found.suggestions.first.map { "\(found.word) → \($0)" }
                    ?? "“\(found.word)” is not in the dictionary.",
                explanation: "“\(found.word)” is not a recognised spelling. If it is a "
                           + "name or a term of art, add it to your dictionary.",
                pname: .misspelled, outcome: .correctness,
                replacements: found.suggestions,
                canBeAddedToDictionary: true))
        }

        // Repeated word: "the the".
        for (index, token) in context.tokens.enumerated() where index > 0 {
            let previous = context.tokens[index - 1]
            guard previous.lower == token.lower, token.lower.count > 1 else { continue }
            // Only when nothing but whitespace separates them.
            let between = context.text.utf16Slice(previous.end, token.begin)
            guard !between.isEmpty, between.allSatisfy({ $0.isWhitespace }) else { continue }
            drafts.append(AlertDraft(
                begin: previous.begin, end: token.end,
                title: "Repeated word",
                details: "Remove the duplicate “\(token.text)”.",
                explanation: "The same word appears twice in a row.",
                pname: .repeatedWord, outcome: .correctness,
                replacements: [previous.text]))
        }
        return drafts
    }

    /// Preserve the original capitalisation pattern on the replacement.
    func matchCase(_ replacement: String, like original: String) -> String {
        if original.allSatisfy({ !$0.isLetter || $0.isUppercase }), original.count > 1 {
            return replacement.uppercased()
        }
        if let first = original.first, first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}

// MARK: - Grammar

/// Article agreement, simple subject–verb agreement and sentence casing.
public struct GrammarPlugin: CheckPlugin {
    public let identifier = "grammar"
    public let feature: FeatureSet = .grammar
    public let languages: Set<Language> = [.english]
    public init() {}

    /// Words beginning with a vowel letter that still take "a", and vice versa.
    static let takesAnDespiteConsonant: Set<String> = ["hour", "honest", "honour", "honor", "heir"]
    static let takesADespiteVowel: Set<String> = ["university", "user", "unit", "union",
                                                  "european", "one", "once", "useful", "unique"]

    static let pluralSubjects: Set<String> = ["they", "we", "you", "these", "those", "people"]
    static let singularSubjects: Set<String> = ["he", "she", "it", "this", "that", "there"]

    public func check(_ context: CheckContext) -> [AlertDraft] {
        var drafts: [AlertDraft] = []
        let tokens = context.tokens

        for (index, token) in tokens.enumerated() {
            // a / an
            if token.lower == "a" || token.lower == "an", index + 1 < tokens.count {
                let next = tokens[index + 1]
                let wantsAn = Self.needsAn(next.lower)
                let isAn = token.lower == "an"
                if wantsAn != isAn {
                    let fix = wantsAn ? "an": "a"
                    drafts.append(AlertDraft(
                        begin: token.begin, end: token.end,
                        highlightBegin: token.begin, highlightEnd: next.end,
                        title: "Incorrect article",
                        details: "Use “\(fix)” before “\(next.text)”.",
                        explanation: "“An” precedes a vowel sound, “a” a consonant sound — "
                                   + "it is the sound that matters, not the letter.",
                        examples: ["an hour", "a university"],
                        pname: .articleAgreement, outcome: .correctness,
                        replacements: [matchCase(fix, like: token.text)]))
                }
            }

            // they was / he have
            if index + 1 < tokens.count {
                let verb = tokens[index + 1]
                if Self.pluralSubjects.contains(token.lower), verb.lower == "was" {
                    drafts.append(agreement(subject: token, verb: verb, fix: "were"))
                }
                if Self.singularSubjects.contains(token.lower), verb.lower == "were" {
                    drafts.append(agreement(subject: token, verb: verb, fix: "was"))
                }
                if Self.singularSubjects.contains(token.lower), verb.lower == "have" {
                    drafts.append(agreement(subject: token, verb: verb, fix: "has"))
                }
                if Self.pluralSubjects.contains(token.lower), verb.lower == "has" {
                    drafts.append(agreement(subject: token, verb: verb, fix: "have"))
                }
            }
        }

        // Sentence must start with a capital.
        for sentence in context.sentences {
            guard let first = context.tokens(in: sentence).first,
                  let initial = first.text.first, initial.isLowercase, initial.isLetter
            else { continue }
            drafts.append(AlertDraft(
                begin: first.begin, end: first.end,
                title: "Capitalise the first word",
                details: "“\(first.text)” starts a sentence.",
                explanation: "Sentences begin with a capital letter.",
                pname: .lowercaseSentenceStart, outcome: .correctness,
                replacements: [first.text.prefix(1).uppercased() + first.text.dropFirst()]))
        }
        return drafts
    }

    private func agreement(subject: Token, verb: Token, fix: String) -> AlertDraft {
        AlertDraft(
            begin: verb.begin, end: verb.end,
            highlightBegin: subject.begin, highlightEnd: verb.end,
            title: "Subject–verb agreement",
            details: "“\(subject.text) \(verb.text)” → “\(subject.text) \(fix)”.",
            explanation: "The verb must agree in number with its subject.",
            pname: .subjectVerbAgreement, outcome: .correctness,
            replacements: [matchCase(fix, like: verb.text)])
    }

    static func needsAn(_ word: String) -> Bool {
        if takesAnDespiteConsonant.contains(word) { return true }
        if takesADespiteVowel.contains(word) { return false }
        guard let first = word.first else { return false }
        return "aeiou".contains(first)
    }

    func matchCase(_ replacement: String, like original: String) -> String {
        guard let first = original.first, first.isUppercase else { return replacement }
        return replacement.prefix(1).uppercased() + replacement.dropFirst()
    }
}

// MARK: - Punctuation

/// Spacing and terminal punctuation.
public struct PunctuationPlugin: CheckPlugin {
    public let identifier = "punctuation"
    public let feature: FeatureSet = .punctuation
    public let languages: Set<Language> = [.english]
    public init() {}

    public func check(_ context: CheckContext) -> [AlertDraft] {
        var drafts: [AlertDraft] = []
        let units = Array(context.text.utf16)

        func char(_ i: Int) -> Character? {
            guard i >= 0, i < units.count else { return nil }
            return Character(UnicodeScalar(units[i]) ?? " ")
        }

        // Runs of spaces are checked by `Spacing`, which French shares. The
        // rules below cannot be shared: French requires the space this one
        // removes.
        drafts.append(contentsOf: Spacing.collapsibleRuns(in: context))

        // Space before,.;: ! ?
        for i in 0..<units.count {
            guard let c = char(i), ",.;:!?".contains(c), i > 0,
                  let previous = char(i - 1), previous == " " else { continue }
            var start = i - 1
            while start > 0, char(start - 1) == " " { start -= 1 }
            drafts.append(AlertDraft(
                begin: start, end: i,
                highlightBegin: start, highlightEnd: i + 1,
                title: "Space before punctuation",
                details: "Remove the space before “\(c)”.",
                explanation: "Punctuation attaches to the word it follows.",
                pname: .spaceBeforePunctuation, outcome: .correctness,
                replacements: [""]))
        }

        // Final sentence has no terminator.
        if let last = context.sentences.last {
            let tail = context.text.utf16Slice(last.begin, last.end)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let final = tail.last, !".!?:;".contains(final),
               // Five words, not three: a short unpunctuated line at the end of
               // a document is far more often a heading or a sign-off than a
               // sentence missing its full stop.
               context.tokens(in: last).count >= 5 {
                drafts.append(AlertDraft(
                    begin: last.end, end: last.end,
                    highlightBegin: max(last.begin, last.end - 12), highlightEnd: last.end,
                    title: "Missing end punctuation",
                    details: "Add a full stop.",
                    explanation: "A complete sentence ends with terminal punctuation.",
                    pname: .missingTerminalPunctuation, outcome: .correctness,
                    replacements: ["."]))
            }
        }
        return drafts
    }
}
