import Foundation
import CorrectorCore
import CorrectorDelta

// MARK: - Clarté

/// Wordiness, passive voice and nominalisation, in French.
public struct FrenchClarityPlugin: CheckPlugin {
    public let identifier = "fr.clarity"
    public let feature: FeatureSet = .clarity
    public let languages: Set<Language> = [.french]
    public init() {}

    static let wordyPhrases: [(phrase: String, replacement: String)] = [
        ("en raison du fait que", "parce que"),
        ("du fait que", "parce que"),
        ("étant donné que", "puisque"),
        ("dans le but de", "pour"),
        ("afin de pouvoir", "pour"),
        ("de manière à", "pour"),
        ("dans le cadre de", "pour"),
        ("au niveau de", "dans"),
        ("en termes de", "pour"),
        ("à l'heure actuelle", "actuellement"),
        ("au jour d'aujourd'hui", "aujourd'hui"),
        ("dans un premier temps", "d'abord"),
        ("un grand nombre de", "beaucoup de"),
        ("la majorité de", "la plupart de"),
        ("un certain nombre de", "plusieurs"),
        ("avoir la possibilité de", "pouvoir"),
        ("être en mesure de", "pouvoir"),
        ("procéder à une vérification", "vérifier"),
        ("prendre une décision", "décider"),
        ("apporter une amélioration", "améliorer"),
        ("il est important de noter que", ""),
        ("il convient de noter que", ""),
        ("force est de constater que", ""),
        ("de façon régulière", "régulièrement"),
        ("sur une base quotidienne", "quotidiennement"),
        ("préalablement à", "avant"),
        ("postérieurement à", "après"),
        ("à proximité de", "près de"),
    ]

    static let beForms: Set<String> = [
        "est", "sont", "était", "étaient", "sera", "seront", "a", "ont",
        "fut", "furent", "soit", "soient",
    ]

    public func check(_ context: CheckContext) -> [AlertDraft] {
        var drafts: [AlertDraft] = []
        let lowered = context.text.lowercased()

        for entry in Self.wordyPhrases {
            var searchStart = lowered.startIndex
            while let range = lowered.range(of: entry.phrase,
                                            range: searchStart..<lowered.endIndex) {
                let begin = lowered.utf16.distance(
                    from: lowered.utf16.startIndex,
                    to: range.lowerBound.samePosition(in: lowered.utf16)!)
                let end = begin + entry.phrase.utf16Length
                let beforeOK = begin == 0 || !isWordCharacter(context.text, begin - 1)
                let afterOK = end >= context.text.utf16Length
                            || !isWordCharacter(context.text, end)
                if beforeOK, afterOK {
                    drafts.append(AlertDraft(
                        begin: begin,
                        end: entry.replacement.isEmpty
                            ? absorbTrailingSpace(context.text, end) : end,
                        highlightBegin: begin, highlightEnd: end,
                        title: entry.replacement.isEmpty
                            ? "Formule creuse": "Tournure lourde",
                        details: entry.replacement.isEmpty
                            ? "« \(entry.phrase) » n'apporte rien."
: "« \(entry.phrase) » → « \(entry.replacement) »",
                        explanation: "Une formulation plus courte dit la même chose "
                                   + "et se lit mieux.",
                        pname: .wordiness, outcome: .clarity,
                        replacements: [entry.replacement]))
                }
                searchStart = range.upperBound
            }
        }

        let tokens = context.tokens
        for (index, token) in tokens.enumerated() where Self.beForms.contains(token.lower) {
            guard index + 1 < tokens.count else { continue }
            var participleIndex = index + 1
            // « a été validé »: skip the auxiliary's own participle.
            if tokens[participleIndex].lower == "été", participleIndex + 1 < tokens.count {
                participleIndex += 1
            }
            guard participleIndex < tokens.count else { continue }
            let participle = tokens[participleIndex]
            guard isLikelyParticiple(participle.lower) else { continue }
            // Require an explicit agent or it is more likely a plain adjective.
            let followedByPar = participleIndex + 1 < tokens.count
                             && tokens[participleIndex + 1].lower == "par"
            guard followedByPar else { continue }

            drafts.append(AlertDraft(
                begin: token.begin, end: participle.end,
                title: "Voix passive",
                details: "Mettez l'acteur en sujet.",
                explanation: "La voix active est plus directe et désigne clairement "
                           + "qui fait l'action.",
                examples: ["le rapport a été écrit par Sam → Sam a écrit le rapport"],
                pname: .passiveVoice, outcome: .clarity))
        }

        // Nominalisation: « la réalisation de » → « réaliser ».
        for (index, token) in tokens.enumerated() where index + 1 < tokens.count {
            let next = tokens[index + 1]
            guard next.lower == "de" || next.lower == "des" || next.lower == "du",
                  token.lower.count > 7,
                  token.lower.hasSuffix("tion") || token.lower.hasSuffix("ment")
                  || token.lower.hasSuffix("tions") else { continue }
            drafts.append(AlertDraft(
                begin: token.begin, end: next.end,
                title: "Nominalisation",
                details: "« \(token.text) \(next.text) » cache un verbe.",
                explanation: "Transformer un verbe en nom allonge la phrase et "
                           + "enfouit l'action.",
                examples: ["la réalisation du projet → réaliser le projet"],
                pname: .nominalization, outcome: .clarity))
        }
        return drafts
    }

    private func isWordCharacter(_ text: String, _ offset: Int) -> Bool {
        guard let ch = text.utf16Slice(from: offset, length: 1).first else { return false }
        return ch.isLetter || ch.isNumber
    }

    private func absorbTrailingSpace(_ text: String, _ end: Int) -> Int {
        guard end < text.utf16Length,
              text.utf16Slice(from: end, length: 1) == " " else { return end }
        return end + 1
    }

    /// Conservative participle test: regular `-é/-ée/-és/-ées` endings plus a
    /// short irregular list.
    private func isLikelyParticiple(_ word: String) -> Bool {
        let irregular: Set<String> = [
            "fait", "faite", "faits", "faites", "dit", "dite", "dits", "dites",
            "mis", "mise", "mises", "pris", "prise", "prises", "écrit", "écrite",
            "ouvert", "ouverte", "couvert", "offert", "produit", "construit",
            "détruit", "reçu", "vu", "lu", "su", "pu", "dû", "connu", "venu",
        ]
        if irregular.contains(word) { return true }
        guard word.count > 3 else { return false }
        return word.hasSuffix("é") || word.hasSuffix("ée")
            || word.hasSuffix("és") || word.hasSuffix("ées")
    }
}

// MARK: - Engagement

/// Filler words and weak intensifiers, in French.
public struct FrenchEngagementPlugin: CheckPlugin {
    public let identifier = "fr.engagement"
    public let feature: FeatureSet = .engagement
    public let languages: Set<Language> = [.french]
    public init() {}

    static let fillers: Set<String> = [
        "vraiment", "franchement", "littéralement", "basiquement",
        "effectivement", "clairement", "évidemment", "simplement",
        "carrément", "typiquement",
    ]

    static let weakIntensifiers: Set<String> = [
        "très", "assez", "plutôt", "relativement", "extrêmement",
        "particulièrement", "vachement", "super",
    ]

    static let longSentenceWords = 30

    public func check(_ context: CheckContext) -> [AlertDraft] {
        var drafts: [AlertDraft] = []

        for token in context.tokens {
            let deleteEnd = absorbTrailingSpace(context.text, token.end)
            if Self.fillers.contains(token.lower) {
                drafts.append(AlertDraft(
                    begin: token.begin, end: deleteEnd,
                    highlightBegin: token.begin, highlightEnd: token.end,
                    title: "Mot de remplissage",
                    details: "« \(token.text) » peut généralement disparaître.",
                    explanation: "Supprimer le remplissage resserre la phrase "
                               + "sans rien lui enlever.",
                    pname: .fillerWord, outcome: .engagement,
                    replacements: [""]))
            } else if Self.weakIntensifiers.contains(token.lower) {
                drafts.append(AlertDraft(
                    begin: token.begin, end: deleteEnd,
                    highlightBegin: token.begin, highlightEnd: token.end,
                    title: "Intensificateur faible",
                    details: "« \(token.text) » affaiblit le mot qu'il modifie.",
                    explanation: "Un mot fort convainc mieux qu'un intensificateur "
                               + "suivi d'un mot tiède.",
                    examples: ["très bon → excellent", "très grand → immense"],
                    pname: .weakIntensifier, outcome: .engagement,
                    replacements: [""]))
            }
        }

        for sentence in context.sentences {
            let count = context.tokens(in: sentence).count
            guard count > Self.longSentenceWords else { continue }
            drafts.append(AlertDraft(
                begin: sentence.begin, end: sentence.end,
                title: "Phrase longue",
                details: "\(count) mots — envisagez de la couper.",
                explanation: "Au-delà d'environ \(Self.longSentenceWords) mots, le "
                           + "lecteur doit retenir trop de choses à la fois.",
                pname: .sentenceLength, outcome: .engagement,
                group: .inline))
        }

        var openers: [(word: String, span: (begin: Int, end: Int))] = []
        for sentence in context.sentences {
            guard let first = context.tokens(in: sentence).first else { continue }
            openers.append((first.lower, sentence))
        }
        var runStart = 0
        while runStart < openers.count {
            var runEnd = runStart
            while runEnd + 1 < openers.count,
                  openers[runEnd + 1].word == openers[runStart].word { runEnd += 1 }
            if runEnd - runStart + 1 >= 3 {
                drafts.append(AlertDraft(
                    begin: openers[runStart].span.begin, end: openers[runEnd].span.end,
                    title: "Débuts de phrase répétitifs",
                    details: "\(runEnd - runStart + 1) phrases de suite commencent par "
                           + "« \(openers[runStart].word) ».",
                    explanation: "Varier les attaques de phrase maintient le rythme.",
                    pname: .monotonousOpeners, outcome: .engagement,
                    group: .inline))
            }
            runStart = runEnd + 1
        }
        return drafts
    }

    private func absorbTrailingSpace(_ text: String, _ end: Int) -> Int {
        guard end < text.utf16Length,
              text.utf16Slice(from: end, length: 1) == " " else { return end }
        return end + 1
    }
}

// MARK: - Inclusivité

/// Gendered or dated terms with neutral French equivalents.
public struct FrenchInclusivityPlugin: CheckPlugin {
    public let identifier = "fr.inclusivity"
    public let feature: FeatureSet = .inclusivity
    public let languages: Set<Language> = [.french]
    public init() {}

    static let replacements: [String: String] = [
        "mademoiselle": "madame",
        "handicapé": "personne en situation de handicap",
        "handicapés": "personnes en situation de handicap",
        "liste noire": "liste de blocage",
        "liste blanche": "liste d'autorisation",
        "maître": "principal",
        "esclave": "réplique",
        "cobaye": "participant",
    ]

    /// Single-word entries are matched on tokens; multi-word ones on the text.
    public func check(_ context: CheckContext) -> [AlertDraft] {
        var drafts: [AlertDraft] = []

        for token in context.tokens {
            guard let fix = Self.replacements[token.lower],
                  !fix.contains(" ") || Self.replacements[token.lower] != nil,
                  !token.lower.contains(" ") else { continue }
            drafts.append(AlertDraft(
                begin: token.begin, end: token.end,
                title: "Terme plus inclusif",
                details: "« \(token.text) » → « \(fix) »",
                explanation: "Un terme neutre touche davantage de lecteurs "
                           + "sans perdre en précision.",
                pname: .inclusiveLanguage, outcome: .inclusivity,
                replacements: [fix]))
        }

        let lowered = context.text.lowercased()
        for (phrase, fix) in Self.replacements where phrase.contains(" ") {
            var searchStart = lowered.startIndex
            while let range = lowered.range(of: phrase, range: searchStart..<lowered.endIndex) {
                let begin = lowered.utf16.distance(
                    from: lowered.utf16.startIndex,
                    to: range.lowerBound.samePosition(in: lowered.utf16)!)
                drafts.append(AlertDraft(
                    begin: begin, end: begin + phrase.utf16Length,
                    title: "Terme plus inclusif",
                    details: "« \(phrase) » → « \(fix) »",
                    explanation: "Un terme neutre touche davantage de lecteurs "
                               + "sans perdre en précision.",
                    pname: .inclusiveLanguage, outcome: .inclusivity,
                    replacements: [fix]))
                searchStart = range.upperBound
            }
        }
        return drafts
    }
}
