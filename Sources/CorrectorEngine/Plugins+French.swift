import Foundation
import CorrectorCore
import CorrectorDelta

// Rules for French.
//
// These are not translations of the English plugins. French needs checks that
// have no English counterpart (elision, the space before double punctuation)
// and must *not* inherit English ones that would be actively wrong on it — the
// English punctuation plugin flags a space before `;`, which French requires.
// That asymmetry is why `CheckPlugin.languages` exists.

// MARK: - Orthographe

/// Accent and spelling corrections.
///
/// Most entries restore a missing diacritic, because that is the error an
/// English keyboard layout produces most often in French.
public struct FrenchSpellingPlugin: CheckPlugin {
    public let identifier = "fr.spelling"
    public let feature: FeatureSet = .spelling
    public let languages: Set<Language> = [.french]

    let dictionary: SpellDictionary

    public init(dictionary: SpellDictionary = TableSpellDictionary.standard) {
        self.dictionary = dictionary
    }

    public static let corrections: [String: String] = [
        // Accents manquants
        "tres": "très", "apres": "après", "deja": "déjà", "etre": "être",
        "meme": "même", "memes": "mêmes", "bientot": "bientôt", "plutot": "plutôt",
        "probleme": "problème", "problemes": "problèmes", "systeme": "système",
        "systemes": "systèmes", "modele": "modèle", "modeles": "modèles",
        "donnees": "données", "resultat": "résultat", "resultats": "résultats",
        "reference": "référence", "references": "références",
        "general": "général", "generale": "générale", "different": "différent",
        "differente": "différente", "differents": "différents",
        "necessaire": "nécessaire", "experience": "expérience",
        "periode": "période", "methode": "méthode", "methodes": "méthodes",
        "numero": "numéro", "theme": "thème", "interet": "intérêt",
        "fenetre": "fenêtre", "fenetres": "fenêtres", "cout": "coût",
        "couts": "coûts", "gout": "goût", "aout": "août", "ile": "île",
        "diner": "dîner", "maitre": "maître", "connaitre": "connaître",
        "parait": "paraît", "entrainement": "entraînement",
        "developpement": "développement", "developper": "développer",
        "evenement": "événement", "evenements": "événements",
        "securite": "sécurité", "qualite": "qualité", "equipe": "équipe",
        "etape": "étape", "etapes": "étapes", "annee": "année", "annees": "années",
        "derniere": "dernière", "premiere": "première", "maniere": "manière",
        "matiere": "matière", "critere": "critère", "criteres": "critères",
        "siege": "siège", "college": "collège", "succes": "succès",
        "proces": "procès", "acces": "accès", "progres": "progrès",
        // Fautes d'orthographe proprement dites
        "parmis": "parmi", "malgres": "malgré", "language": "langage",
        "connection": "connexion", "addresse": "adresse", "adresse": "adresse",
        "apartement": "appartement", "develloper": "développer",
        "proffesseur": "professeur", "exellent": "excellent", "acceuil": "accueil",
        "parceque": "parce que", "quelquefois": "quelquefois",
        "entrainer": "entraîner", "apelle": "appelle", "apeler": "appeler",
        "vraisemblablement": "vraisemblablement", "dificile": "difficile",
        "diférent": "différent", "resoudre": "résoudre", "reussir": "réussir",
        // Vocabulaire courant des documents professionnels.
        "delai": "délai", "delais": "délais", "separee": "séparée",
        "separe": "séparé", "separes": "séparés", "separees": "séparées",
        "debordee": "débordée", "recu": "reçu", "decision": "décision",
        "controle": "contrôle", "enquete": "enquête", "arreter": "arrêter",
        "pret": "prêt", "tete": "tête", "benefice": "bénéfice",
        "strategie": "stratégie", "clientele": "clientèle",
        "parametre": "paramètre", "parametres": "paramètres",
        "creer": "créer", "creation": "création", "operation": "opération",
        "verification": "vérification", "integration": "intégration",
        "reunion": "réunion", "realiser": "réaliser", "preferer": "préférer",
    ]

    public func check(_ context: CheckContext) -> [AlertDraft] {
        var drafts: [AlertDraft] = []

        for found in dictionary.misspellings(in: context.text,
                                             tokens: context.tokens,
                                             language: .french,
                                             dialect: context.dialect) {
            drafts.append(AlertDraft(
                begin: found.begin, end: found.end,
                title: "Orthographe",
                details: found.suggestions.first.map { "« \(found.word) » → « \($0) »" }
                    ?? "« \(found.word) » est absent du dictionnaire.",
                explanation: "« \(found.word) » n'est pas une graphie reconnue. "
                           + "S'il s'agit d'un nom propre ou d'un terme technique, "
                           + "ajoutez-le au dictionnaire.",
                pname: .misspelled, outcome: .correctness,
                replacements: found.suggestions,
                canBeAddedToDictionary: true))
        }

        // Répétition de mot.
        for (index, token) in context.tokens.enumerated() where index > 0 {
            let previous = context.tokens[index - 1]
            guard previous.lower == token.lower, token.lower.count > 1 else { continue }
            let between = context.text.utf16Slice(previous.end, token.begin)
            guard !between.isEmpty, between.allSatisfy({ $0.isWhitespace }) else { continue }
            drafts.append(AlertDraft(
                begin: previous.begin, end: token.end,
                title: "Mot répété",
                details: "Supprimez le doublon « \(token.text) ».",
                explanation: "Le même mot apparaît deux fois de suite.",
                pname: .repeatedWord, outcome: .correctness,
                replacements: [previous.text]))
        }
        return drafts
    }

    func matchCase(_ replacement: String, like original: String) -> String {
        guard let first = original.first, first.isUppercase else { return replacement }
        return replacement.prefix(1).uppercased() + replacement.dropFirst()
    }
}

// MARK: - Grammaire

/// Elision, the conditional after « si », and a few classic mistakes.
public struct FrenchGrammarPlugin: CheckPlugin {
    public let identifier = "fr.grammar"
    public let feature: FeatureSet = .grammar
    public let languages: Set<Language> = [.french]
    public init() {}

    /// Words that elide before a vowel, and what they become.
    ///
    /// Direct counterpart of the English a/an rule: both are a function word
    /// changing shape according to the sound that follows it.
    static let elidable: [String: String] = [
        "le": "l'", "la": "l'", "de": "d'", "je": "j'", "me": "m'",
        "te": "t'", "se": "s'", "ne": "n'", "ce": "c'", "que": "qu'",
    ]

    /// Conditional forms that must not follow « si ».
    static let conditionals: [String: String] = [
        "aurais": "avais", "aurait": "avait", "aurions": "avions",
        "auriez": "aviez", "auraient": "avaient",
        "serais": "étais", "serait": "était", "serions": "étions",
        "seriez": "étiez", "seraient": "étaient",
    ]

    static let vowels = Set("aeiouéèêëàâîïôöùûü")

    public func check(_ context: CheckContext) -> [AlertDraft] {
        var drafts: [AlertDraft] = []
        let tokens = context.tokens

        for (index, token) in tokens.enumerated() {
            // Élision: « le ami » → « l'ami ».
            if let elided = Self.elidable[token.lower], index + 1 < tokens.count {
                let next = tokens[index + 1]
                // Only before a plain vowel. French `h` is skipped on purpose:
                // mute h elides ("l'homme") but aspirated h does not
                // ("le héros"), and the two are indistinguishable without a
                // dictionary — so flagging either would be a coin toss.
                if let initial = next.lower.first, Self.vowels.contains(initial),
                   context.text.utf16Slice(token.end, next.begin) == " " {
                    drafts.append(AlertDraft(
                        begin: token.begin, end: next.begin,
                        highlightBegin: token.begin, highlightEnd: next.end,
                        title: "Élision manquante",
                        details: "« \(token.text) \(next.text) » → « \(elided)\(next.text) »",
                        explanation: "Devant une voyelle, « \(token.lower) » s'élide "
                                   + "en « \(elided) ».",
                        examples: ["l'ami", "d'accord", "qu'il"],
                        pname: .elision, outcome: .correctness,
                        replacements: [matchCase(elided, like: token.text)]))
                }
            }

            // Pas de conditionnel après « si ».
            if token.lower == "si", index + 1 < tokens.count {
                // Allow one pronoun between: « si je serais ».
                for offset in 1...min(2, tokens.count - index - 1) {
                    let candidate = tokens[index + offset]
                    if let imparfait = Self.conditionals[candidate.lower] {
                        drafts.append(AlertDraft(
                            begin: candidate.begin, end: candidate.end,
                            highlightBegin: token.begin, highlightEnd: candidate.end,
                            title: "Conditionnel après « si »",
                            details: "« \(candidate.text) » → « \(imparfait) »",
                            explanation: "Après « si » de condition, on emploie "
                                       + "l'imparfait, jamais le conditionnel.",
                            examples: ["si j'avais su", "s'il était là"],
                            pname: .conditionalAfterSi, outcome: .correctness,
                            replacements: [imparfait]))
                        break
                    }
                }
            }

            // « malgré que » → « bien que ».
            if token.lower == "malgré", index + 1 < tokens.count,
               tokens[index + 1].lower == "que" {
                drafts.append(AlertDraft(
                    begin: token.begin, end: tokens[index + 1].end,
                    title: "« malgré que »",
                    details: "→ « bien que »",
                    explanation: "« Malgré que » est critiqué hors de l'expression "
                               + "« malgré que j'en aie ». Préférez « bien que ».",
                    pname: .malgreQue, outcome: .correctness,
                    replacements: [matchCase("bien que", like: token.text)]))
            }

            // « pallier à » → « pallier ».
            if token.lower.hasPrefix("palli"), index + 1 < tokens.count,
               tokens[index + 1].lower == "à" {
                drafts.append(AlertDraft(
                    begin: token.end, end: tokens[index + 1].end,
                    highlightBegin: token.begin, highlightEnd: tokens[index + 1].end,
                    title: "« pallier » est transitif direct",
                    details: "Supprimez « à ».",
                    explanation: "On pallie quelque chose, et non à quelque chose.",
                    pname: .pallierA, outcome: .correctness,
                    replacements: [""]))
            }
        }

        // Majuscule en début de phrase.
        for sentence in context.sentences {
            guard let first = context.tokens(in: sentence).first,
                  let initial = first.text.first, initial.isLowercase, initial.isLetter
            else { continue }
            drafts.append(AlertDraft(
                begin: first.begin, end: first.end,
                title: "Majuscule attendue",
                details: "« \(first.text) » commence une phrase.",
                explanation: "Une phrase commence par une majuscule.",
                pname: .lowercaseSentenceStart, outcome: .correctness,
                replacements: [first.text.prefix(1).uppercased() + first.text.dropFirst()]))
        }
        return drafts
    }

    func matchCase(_ replacement: String, like original: String) -> String {
        guard let first = original.first, first.isUppercase else { return replacement }
        return replacement.prefix(1).uppercased() + replacement.dropFirst()
    }
}
