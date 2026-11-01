import Foundation
import CorrectorCore
import CorrectorDelta

// MARK: - Clarity

/// Wordiness, passive voice and nominalisation.
public struct ClarityPlugin: CheckPlugin {
    public let identifier = "clarity"
    public let feature: FeatureSet = .clarity
    public let languages: Set<Language> = [.english]
    public init() {}

    /// Multi-word phrases with a shorter equivalent. Corrector's own table.
    static let wordyPhrases: [(phrase: String, replacement: String)] = [
        ("in order to", "to"),
        ("due to the fact that", "because"),
        ("at this point in time", "now"),
        ("at the present time", "now"),
        ("in the event that", "if"),
        ("for the purpose of", "to"),
        ("in the near future", "soon"),
        ("a large number of", "many"),
        ("a majority of", "most"),
        ("has the ability to", "can"),
        ("is able to", "can"),
        ("in spite of the fact that", "although"),
        ("with regard to", "about"),
        ("in terms of", "for"),
        ("it is important to note that", ""),
        ("needless to say", ""),
        ("make a decision", "decide"),
        ("come to an agreement", "agree"),
        ("give consideration to", "consider"),
        ("take into account", "consider"),
        ("on a daily basis", "daily"),
        ("in the process of", ""),
        ("prior to", "before"),
        ("subsequent to", "after"),
        ("in close proximity to", "near"),
        ("a number of", "several"),
    ]

    static let beForms: Set<String> = ["is", "are", "was", "were", "be", "been", "being", "am"]

    public func check(_ context: CheckContext) -> [AlertDraft] {
        var drafts: [AlertDraft] = []
        let lowered = context.text.lowercased()

        // Wordy phrases, matched on the lowercased text and mapped back to
        // UTF-16 offsets.
        for entry in Self.wordyPhrases {
            var searchStart = lowered.startIndex
            while let range = lowered.range(of: entry.phrase, range: searchStart..<lowered.endIndex) {
                let begin = lowered.utf16.distance(from: lowered.utf16.startIndex,
                                                   to: range.lowerBound.samePosition(in: lowered.utf16)!)
                let end = begin + entry.phrase.utf16Length
                // Must sit on word boundaries.
                let beforeOK = begin == 0 || !isWordChar(context.text, begin - 1)
                let afterOK = end >= context.text.utf16Length || !isWordChar(context.text, end)
                if beforeOK, afterOK {
                    let replacement = entry.replacement
                    drafts.append(AlertDraft(
                        begin: begin, end: replacement.isEmpty ? trimTrailingSpace(context.text, end) : end,
                        title: replacement.isEmpty ? "Remove the filler phrase": "Wordy phrase",
                        details: replacement.isEmpty
                            ? "“\(entry.phrase)” adds no information."
: "“\(entry.phrase)” → “\(replacement)”.",
                        explanation: "Shorter phrasing is easier to read and carries the same meaning.",
                        examples: replacement.isEmpty ? [] : ["\(entry.phrase) → \(replacement)"],
                        pname: .wordiness, outcome: .clarity,
                        replacements: [replacement]))
                }
                searchStart = range.upperBound
            }
        }

        // Passive voice: a form of "be" followed by a past participle.
        let tokens = context.tokens
        for (index, token) in tokens.enumerated() where Self.beForms.contains(token.lower) {
            guard index + 1 < tokens.count else { continue }
            var participleIndex = index + 1
            // Allow one adverb in between: "was quickly resolved".
            if tokens[participleIndex].lower.hasSuffix("ly"), participleIndex + 1 < tokens.count {
                participleIndex += 1
            }
            let participle = tokens[participleIndex]
            guard isLikelyPastParticiple(participle.lower) else { continue }
            drafts.append(AlertDraft(
                begin: token.begin, end: participle.end,
                title: "Passive voice",
                details: "Consider naming who performs the action.",
                explanation: "Active voice puts the actor first, which usually reads as more "
                           + "direct and assigns responsibility clearly.",
                examples: ["The report was written by Sam → Sam wrote the report"],
                pname: .passiveVoice, outcome: .clarity))
        }

        // Nominalisation: "-tion of", "-ment of".
        for (index, token) in tokens.enumerated() where index + 1 < tokens.count {
            let next = tokens[index + 1]
            guard next.lower == "of", token.lower.count > 6,
                  token.lower.hasSuffix("tion") || token.lower.hasSuffix("ment")
            else { continue }
            drafts.append(AlertDraft(
                begin: token.begin, end: next.end,
                title: "Nominalisation",
                details: "“\(token.text) of” hides a verb.",
                explanation: "Turning a verb into a noun lengthens the sentence and buries "
                           + "the action.",
                examples: ["the implementation of the plan → implementing the plan"],
                pname: .nominalization, outcome: .clarity))
        }
        return drafts
    }

    private func isWordChar(_ text: String, _ utf16Offset: Int) -> Bool {
        let s = text.utf16Slice(from: utf16Offset, length: 1)
        guard let ch = s.first else { return false }
        return ch.isLetter || ch.isNumber
    }

    private func trimTrailingSpace(_ text: String, _ end: Int) -> Int {
        var e = end
        while e < text.utf16Length, text.utf16Slice(from: e, length: 1) == " " { e += 1 }
        return e
    }

    /// Heuristic past-participle test. Accepts regular `-ed` forms plus a small
    /// irregular list; deliberately conservative to limit false positives.
    private func isLikelyPastParticiple(_ word: String) -> Bool {
        let irregular: Set<String> = [
            "done", "made", "given", "taken", "seen", "written", "known", "shown",
            "found", "held", "built", "sent", "kept", "left", "told", "brought",
            "bought", "caught", "chosen", "driven", "eaten", "fallen", "forgotten",
            "gotten", "hidden", "lost", "paid", "put", "read", "run", "said", "sold",
            "spoken", "spent", "stolen", "taught", "thrown", "understood", "worn",
        ]
        if irregular.contains(word) { return true }
        guard word.hasSuffix("ed"), word.count > 4 else { return false }
        // Exclude adjectives that merely end in -ed and common false friends.
        let notParticiples: Set<String> = ["need", "indeed", "embed", "exceed", "proceed",
                                           "succeed", "speed", "breed", "feed", "bed", "red"]
        return !notParticiples.contains(word)
    }
}

// MARK: - Engagement

/// Filler words, weak intensifiers, sentence length and repeated openers.
public struct EngagementPlugin: CheckPlugin {
    public let identifier = "engagement"
    public let feature: FeatureSet = .engagement
    public let languages: Set<Language> = [.english]
    public init() {}

    static let fillers: Set<String> = [
        "basically", "actually", "literally", "honestly", "obviously",
        "essentially", "simply", "just", "really", "truly", "totally",
    ]

    static let weakIntensifiers: [String: String] = [
        "very": "", "quite": "", "rather": "", "somewhat": "",
        "fairly": "", "pretty": "", "extremely": "",
    ]

    /// Sentences longer than this read as hard work.
    static let longSentenceWords = 30

    public func check(_ context: CheckContext) -> [AlertDraft] {
        var drafts: [AlertDraft] = []

        for token in context.tokens {
            // Deleting a word must take one adjoining space with it, or
            // accepting the suggestion leaves a double space behind.
            let deleteEnd = absorbingTrailingSpace(context.text, from: token.end)

            if Self.fillers.contains(token.lower) {
                drafts.append(AlertDraft(
                    begin: token.begin, end: deleteEnd,
                    highlightBegin: token.begin, highlightEnd: token.end,
                    title: "Filler word",
                    details: "“\(token.text)” can usually go.",
                    explanation: "Removing filler tightens the sentence without changing it.",
                    pname: .fillerWord, outcome: .engagement,
                    replacements: [""]))
            } else if Self.weakIntensifiers[token.lower] != nil {
                drafts.append(AlertDraft(
                    begin: token.begin, end: deleteEnd,
                    highlightBegin: token.begin, highlightEnd: token.end,
                    title: "Weak intensifier",
                    details: "“\(token.text)” weakens the word it modifies.",
                    explanation: "A stronger single word is more convincing than an "
                               + "intensifier plus a mild one.",
                    examples: ["very good → excellent", "quite large → substantial"],
                    pname: .weakIntensifier, outcome: .engagement,
                    replacements: [""]))
            }
        }

        // Overlong sentences.
        for sentence in context.sentences {
            let count = context.tokens(in: sentence).count
            guard count > Self.longSentenceWords else { continue }
            drafts.append(AlertDraft(
                begin: sentence.begin, end: sentence.end,
                title: "Long sentence",
                details: "\(count) words — consider splitting it.",
                explanation: "Sentences beyond about \(Self.longSentenceWords) words force the "
                           + "reader to hold too much at once.",
                pname: .sentenceLength, outcome: .engagement,
                group: .inline))
        }

        // Three or more consecutive sentences opening with the same word.
        var openers: [(word: String, span: (begin: Int, end: Int))] = []
        for sentence in context.sentences {
            guard let first = context.tokens(in: sentence).first else { continue }
            openers.append((first.lower, sentence))
        }
        var runStart = 0
        while runStart < openers.count {
            var runEnd = runStart
            while runEnd + 1 < openers.count, openers[runEnd + 1].word == openers[runStart].word {
                runEnd += 1
            }
            if runEnd - runStart + 1 >= 3 {
                drafts.append(AlertDraft(
                    begin: openers[runStart].span.begin, end: openers[runEnd].span.end,
                    title: "Repetitive sentence openers",
                    details: "\(runEnd - runStart + 1) sentences in a row start with "
                           + "“\(openers[runStart].word)”.",
                    explanation: "Varying how sentences begin keeps a paragraph moving.",
                    pname: .monotonousOpeners, outcome: .engagement,
                    group: .inline))
            }
            runStart = runEnd + 1
        }
        return drafts
    }

    /// Extend a deletion over one following space, when there is one.
    private func absorbingTrailingSpace(_ text: String, from end: Int) -> Int {
        guard end < text.utf16Length, text.utf16Slice(from: end, length: 1) == " " else {
            return end
        }
        return end + 1
    }
}

// MARK: - Style guide

/// Serial-comma convention.
public struct StyleGuidePlugin: CheckPlugin {
    public let identifier = "styleGuide"
    public let feature: FeatureSet = .styleGuide
    public let languages: Set<Language> = [.english]
    public init() {}

    public func check(_ context: CheckContext) -> [AlertDraft] {
        var drafts: [AlertDraft] = []
        let tokens = context.tokens

        // "a, b and c" → suggest "a, b, and c".
        for (index, token) in tokens.enumerated()
        where token.lower == "and" || token.lower == "or" {
            guard index >= 1, index + 1 < tokens.count else { continue }
            let previous = tokens[index - 1]
            let between = context.text.utf16Slice(previous.end, token.begin)
            guard !between.contains(",") else { continue }

            // Require an earlier comma in the same sentence — i.e. a real list.
            guard let sentence = context.sentences.first(where: {
                token.begin >= $0.begin && token.end <= $0.end
            }) else { continue }
            let head = context.text.utf16Slice(sentence.begin, previous.end)
            guard head.contains(",") else { continue }

            drafts.append(AlertDraft(
                begin: previous.end, end: previous.end,
                highlightBegin: previous.begin, highlightEnd: token.end,
                title: "Serial comma",
                details: "Add a comma before “\(token.text)”.",
                explanation: "This style guide uses the serial (Oxford) comma in lists of "
                           + "three or more.",
                examples: ["red, white, and blue"],
                pname: .oxfordComma, outcome: .styleGuide,
                replacements: [","]))
        }
        return drafts
    }
}

// MARK: - Inclusivity

/// Gendered and dated terms with neutral equivalents.
public struct InclusivityPlugin: CheckPlugin {
    public let identifier = "inclusivity"
    public let feature: FeatureSet = .inclusivity
    public let languages: Set<Language> = [.english]
    public init() {}

    static let replacements: [String: String] = [
        "chairman": "chair", "chairmen": "chairs",
        "manpower": "workforce", "mankind": "humanity",
        "policeman": "police officer", "policemen": "police officers",
        "fireman": "firefighter", "firemen": "firefighters",
        "stewardess": "flight attendant", "salesman": "salesperson",
        "salesmen": "salespeople", "businessman": "businessperson",
        "manmade": "artificial", "freshman": "first-year student",
        "whitelist": "allowlist", "blacklist": "blocklist",
        "master": "primary", "slave": "replica",
        "sanity check": "quick check", "grandfathered": "legacy",
        "guys": "everyone", "crazy": "surprising", "dummy": "placeholder",
    ]

    public func check(_ context: CheckContext) -> [AlertDraft] {
        context.tokens.compactMap { token in
            guard let fix = Self.replacements[token.lower] else { return nil }
            return AlertDraft(
                begin: token.begin, end: token.end,
                title: "Consider a more inclusive term",
                details: "“\(token.text)” → “\(fix)”.",
                explanation: "A neutral term reaches more readers without losing precision.",
                pname: .inclusiveLanguage, outcome: .inclusivity,
                replacements: [fix])
        }
    }
}
