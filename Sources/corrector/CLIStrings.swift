import Foundation
import CorrectorCore

/// Interface language for the command line.
///
/// Follows the system's preferred language, overridable with `--ui`. Kept
/// separate from the document's dialect: proofreading English text from a
/// French shell is perfectly ordinary.
enum CLILocale: String, CaseIterable {
    case english, french

    static var system: CLILocale {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("fr") ? .french : .english
    }
}

/// Command-line strings, in the same compile-time-checked style as the app's:
/// a missing translation is a build error rather than a silent fallback.
struct CLIStrings {
    let locale: CLILocale
    private func pick(_ english: String, _ french: String) -> String {
        locale == .french ? french : english
    }

    // Report sections
    var score: String        { pick("Score", "Score") }
    var tone: String         { pick("tone", "ton") }
    var noSuggestions: String { pick("No suggestions — this reads well.",
                                     "Aucune suggestion — ce texte se lit bien.") }
    func suggestionCount(_ n: Int) -> String {
        "\(n) suggestion\(n == 1 ? "" : "s")"
    }

    /// Per-category count on the score panel.
    func issueCount(_ n: Int) -> String {
        locale == .french
            ? "\(n) problème\(n == 1 ? "" : "s")"
            : "\(n) issue\(n == 1 ? "" : "s")"
    }

    // Stats
    var words: String        { pick("words", "mots") }
    var sentences: String    { pick("sentences", "phrases") }
    var characters: String   { pick("characters", "caractères") }
    var uniqueWords: String  { pick("unique words", "mots uniques") }
    var rareWords: String    { pick("rare words", "mots rares") }
    var wordLength: String   { pick("word length", "longueur des mots") }
    var sentenceLength: String { pick("sentence len", "longueur phrases") }
    var readability: String  { pick("readability", "lisibilité") }
    var reading: String      { pick("reading", "lecture") }
    var speaking: String     { pick("speaking", "parole") }
    var percentile: String   { pick("pct", "centile") }

    // fix command
    func applied(_ n: Int, remaining: Int) -> String {
        locale == .french
            ? "\(n) correction\(n == 1 ? "" : "s") appliquée\(n == 1 ? "" : "s") ; "
            + "\(remaining) nécessite\(remaining == 1 ? "" : "nt") un humain"
            : "applied \(n) suggestion\(n == 1 ? "" : "s"); "
            + "\(remaining) left needing a human"
    }

    // samples command
    var bundledSamples: String { pick("Bundled samples", "Exemples fournis") }

    var deleteReplacement: String { pick("(delete)", "(supprimer)") }

    func outcome(_ outcome: CardLayout.Outcome) -> String {
        guard locale == .french else { return outcome.title }
        switch outcome {
        case .correctness: return "Correction"
        case .clarity:     return "Clarté"
        case .engagement:  return "Engagement"
        case .delivery:    return "Ton"
        case .styleGuide:  return "Typographie"
        case .inclusivity: return "Inclusivité"
        }
    }

    func toneName(_ key: String) -> String {
        guard locale == .french else { return key }
        switch key {
        case "neutral":   return "neutre"
        case "detached":  return "distant"
        case "tentative": return "hésitant"
        case "informal":  return "familier"
        default:          return key
        }
    }

    func readabilityLabel(_ score: Int) -> String {
        guard locale == .french else { return TextStats.describe(score) }
        switch score {
        case 90...:   return "Très facile à lire"
        case 70..<90: return "Facile à lire"
        case 60..<70: return "Français courant"
        case 50..<60: return "Assez difficile"
        case 30..<50: return "Difficile"
        default:      return "Très difficile"
        }
    }

    var usage: String {
        locale == .french ? Self.usageFrench : Self.usageEnglish
    }

    static let usageEnglish = """
    corrector — an offline writing assistant for macOS

    USAGE
      corrector check  <file|-> [options]     Check a document and print suggestions
      corrector fix    <file|-> [options]     Apply every suggestion, print the result
      corrector stats  <file|-> [options]     Readability and length statistics only
      corrector demo                          Run the built-in walkthrough
      corrector samples                       List bundled sample documents

    OPTIONS
      --json                  Emit machine-readable JSON instead of cards
      --only <c,...>          Limit checks: spelling,grammar,punctuation,
                              clarity,engagement,styleGuide,inclusivity
      --language <l>          english | french   (picks that language's defaults)
      --dialect <d>           english: american | british | canadian |
                                       australian | indian
                              french:  french | canadianFrench | belgianFrench |
                                       swissFrench
                              auto     detect from the text (default)
      --ui <l>                Interface language: english | french
      --transient             Treat the input as an ephemeral field
      --no-color              Disable ANSI colour
      --cards                 Print expanded cards instead of the compact list
      -h, --help              This message

    Samples resolve by name: `corrector check memo`, `corrector check note-fr`.
    """

    static let usageFrench = """
    corrector — assistant de rédaction hors ligne pour macOS

    UTILISATION
      corrector check  <fichier|-> [options]  Vérifie un document et liste les suggestions
      corrector fix    <fichier|-> [options]  Applique tout et affiche le résultat
      corrector stats  <fichier|-> [options]  Statistiques de lisibilité seulement
      corrector demo                          Déroule la démonstration intégrée
      corrector samples                       Liste les documents d'exemple

    OPTIONS
      --json                  Sortie JSON exploitable par une machine
      --only <c,...>          Limite les vérifications : spelling,grammar,punctuation,
                              clarity,engagement,styleGuide,inclusivity
      --language <l>          english | french   (choisit les réglages de la langue)
      --dialect <d>           anglais : american | british | canadian |
                                        australian | indian
                              français : french | canadianFrench | belgianFrench |
                                        swissFrench
                              auto      détection depuis le texte (défaut)
      --ui <l>                Langue de l'interface : english | french
      --transient             Traite l'entrée comme un champ éphémère
      --no-color              Désactive la couleur ANSI
      --cards                 Cartes dépliées au lieu de la liste compacte
      -h, --help              Ce message

    Les exemples se résolvent par nom : `corrector check memo`, `corrector check note-fr`.
    """
}
