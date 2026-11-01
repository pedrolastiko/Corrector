import Foundation
import CorrectorCore

/// The interface language.
///
/// Kept separate from the document's dialect on purpose: someone can perfectly
/// well proofread English text in a French interface, and the reverse. Tying
/// the two together would mean changing one to change the other.
public enum UILocale: String, CaseIterable, Identifiable {
    case english
    case french

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case.english: return "English"
        case.french:  return "Français"
        }
    }

    /// Follow the system's preferred languages on first launch.
    public static var system: UILocale {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("fr") ? .french : .english
    }
}

/// Interface strings.
///
/// A plain switch rather than `.strings` files: the set is small, it stays
/// compile-time checked (a missing translation is a build error, not a silent
/// fallback to the key), and it keeps the app a single SwiftPM target with no
/// resource bundle to assemble into the `.app`.
public struct Strings {
    public let locale: UILocale

    public init(locale: UILocale) { self.locale = locale }

    private func pick(_ english: String, _ french: String) -> String {
        locale == .french ? french : english
    }

    // Toolbar and chrome
    public var dialect: String           { pick("Dialect", "Dialecte") }
    public var checks: String            { pick("Checks", "Vérifications") }
    public var acceptAll: String         { pick("Accept All", "Tout accepter") }
    public var interfaceLanguage: String { pick("Interface", "Interface") }
    public var detectAutomatically: String { pick("Detect automatically", "Détection automatique") }

    // Scores
    public var overallScore: String { pick("Overall score", "Score global") }
    public var tone: String         { pick("tone", "ton") }

    // Stats
    public var words: String        { pick("Words", "Mots") }
    public var sentences: String    { pick("Sentences", "Phrases") }
    public var readability: String  { pick("Readability", "Lisibilité") }
    public var readingTime: String  { pick("Reading time", "Temps de lecture") }
    public var speakingTime: String { pick("Speaking time", "Temps de parole") }

    /// Counts agree with their noun. A grammar checker writing "1 phrases"
    /// undermines itself.
    public func wordCount(_ n: Int) -> String {
        locale == .french ? "\(n) mot\(n == 1 ? "" : "s")"
                          : "\(n) word\(n == 1 ? "" : "s")"
    }

    public func sentenceCount(_ n: Int) -> String {
        locale == .french ? "\(n) phrase\(n == 1 ? "" : "s")"
                          : "\(n) sentence\(n == 1 ? "" : "s")"
    }

    public func suggestionCount(_ n: Int) -> String {
        locale == .french ? "\(n) suggestion\(n == 1 ? "" : "s")"
                          : "\(n) suggestion\(n == 1 ? "" : "s")"
    }

    /// Language names follow the interface, not the language itself.
    public func languageName(_ language: Language) -> String {
        switch (language, locale) {
        case (.english, .french): return "Anglais"
        case (.french, .english): return "French"
        default: return language.displayName
        }
    }

    // Cards
    public var noSuggestions: String     { pick("No suggestions", "Aucune suggestion") }
    public var readsWell: String         { pick("This reads well.", "Ce texte se lit bien.") }
    public var accept: String            { pick("Accept", "Accepter") }
    public var dismiss: String           { pick("Dismiss", "Ignorer") }
    public var muteRule: String          { pick("Mute rule", "Masquer la règle") }
    public var addToDictionary: String   { pick("Add to dictionary", "Ajouter au dictionnaire") }
    public var alsoSuggestions: String   { pick("Also", "Aussi") }
    public var deleteReplacement: String { pick("(delete)", "(supprimer)") }

    public var copy: String          { pick("Copy to Clipboard", "Copier dans le presse-papiers") }
    public var copySelection: String { pick("Copy Selection", "Copier la sélection") }
    public var copyAll: String       { pick("Copy All", "Tout copier") }
    public var copied: String        { pick("Copied", "Copié") }

    /// Says how many corrections landed, because the user is looking at
    /// another application and a replacement they did not watch happen is
    /// worth being specific about.
    ///
    /// French and English disagree here: English pluralises "correction" from
    /// two, French from two as well, but French also keeps "appliquée"
    /// agreeing with it. Spelling that out beats interpolating a bare count
    /// into a fixed sentence, which is how "1 phrases" got shipped in a
    /// grammar checker.
    public func quickCorrected(_ count: Int) -> String {
        count == 1
            ? pick("1 correction applied", "1 correction appliquée")
            : pick("\(count) corrections applied", "\(count) corrections appliquées")
    }

    // Version
    public var version: String      { pick("version", "version") }
    public var whatsNew: String     { pick("What’s new", "Nouveautés") }
    public var newFeatures: String  { pick("New", "Nouveautés") }
    public var bugFixes: String     { pick("Fixed", "Corrections") }
    /// The document's own edit counter, shown as a technical detail rather
    /// than as a version — the two were previously confused in the footer.
    public func documentRevision(_ n: Int) -> String {
        pick("document revision \(n)", "révision du document \(n)")
    }

    public var quickCorrected: String      { pick("Selection corrected", "Sélection corrigée") }
    public var quickRefusedSecureField: String {
        pick("Corrector does not read password fields",
             "Corrector ne lit pas les champs de mot de passe")
    }
    public func quickRefusedApplication(_ name: String) -> String {
        pick("Corrector is disabled in \(name)",
             "Corrector est désactivé dans \(name)")
    }
    public var quickAlreadyCorrect: String { pick("Nothing to correct", "Rien à corriger") }
    public var quickNothingSelected: String {
        pick("No text selected", "Aucun texte sélectionné")
    }
    public var quickNeedsPermission: String {
        pick("Allow Corrector in Accessibility settings",
             "Autorisez Corrector dans Accessibilité")
    }
    public var quickCorrect: String        { pick("Correct Selection Anywhere",
                                           "Corriger la sélection, partout") }

    // Menus
    public var newDocument: String  { pick("New Document", "Nouveau document") }
    public var open: String         { pick("Open…", "Ouvrir…") }
    public var checkMenu: String    { pick("Check", "Vérifier") }
    public var checkNow: String     { pick("Check Now", "Vérifier maintenant") }
    public var quit: String         { pick("Quit Corrector", "Quitter Corrector") }
    public var showWindow: String   { pick("Show Window", "Afficher la fenêtre") }
    public var suggestionsCount: String { pick("suggestions", "suggestions") }
    public var suggestionCount: String  { pick("suggestion", "suggestion") }

    // Category names, so the sidebar follows the interface rather than the text
    public func outcome(_ outcome: CardLayout.Outcome) -> String {
        switch (outcome, locale) {
        case (_, .english):      return outcome.title
        case (.correctness, _):  return "Correction"
        case (.clarity, _):      return "Clarté"
        case (.engagement, _):   return "Engagement"
        case (.delivery, _):     return "Ton"
        case (.styleGuide, _):   return "Typographie"
        case (.inclusivity, _):  return "Inclusivité"
        }
    }

    /// `Scores.tone` carries a stable key so it can be translated here rather
    /// than baked into the engine in one language.
    public func toneName(_ key: String) -> String {
        guard locale == .french else { return key }
        switch key {
        case "neutral":   return "neutre"
        case "detached":  return "distant"
        case "tentative": return "hésitant"
        case "informal":  return "familier"
        default:          return key
        }
    }

    public func readabilityLabel(_ score: Int) -> String {
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
}
