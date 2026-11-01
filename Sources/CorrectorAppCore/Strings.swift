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
    public var clear: String         { pick("Clear", "Effacer") }

    // Login item
    public var openAtLogin: String { pick("Open at Login", "Ouvrir au démarrage") }
    /// Shown instead of a tick when macOS has the registration but the user
    /// has not allowed it. Clicking opens the pane where they can.
    public var loginNeedsApproval: String {
        pick("Allow at login in System Settings…",
             "Autoriser au démarrage dans Réglages…")
    }
    /// Shown when the system will not register this bundle at all.
    public var loginUnavailable: String {
        pick("Open at Login (unavailable from this folder)",
             "Ouvrir au démarrage (indisponible depuis ce dossier)")
    }
    /// The same button after a clear. Offering the way back is what makes a
    /// one-click destructive action reasonable in a toolbar.
    public var undoClear: String     { pick("Undo clear", "Annuler l’effacement") }
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

    // Settings
    public var settings: String        { pick("Settings\u{2026}", "R\u{e9}glages\u{2026}") }
    public var settingsGeneral: String { pick("General", "G\u{e9}n\u{e9}ral") }
    public var settingsChecks: String  { pick("Checks", "V\u{e9}rifications") }
    public var settingsDictionary: String { pick("Dictionary", "Dictionnaire") }
    public var settingsRules: String   { pick("Rules", "R\u{e8}gles") }
    public var settingsShortcut: String { pick("Shortcut", "Raccourci") }
    public var settingsUpdates: String { pick("Updates", "Mises \u{e0} jour") }

    public var addWord: String         { pick("Add a word\u{2026}", "Ajouter un mot\u{2026}") }
    public var remove: String          { pick("Remove", "Retirer") }
    /// Not `accept`: that one means "take this suggestion", and reusing it
    /// on a form button made the settings screen say "Accept" under a text
    /// field where the only thing to accept is a word you just typed.
    public var addToList: String       { pick("Add", "Ajouter") }
    public var restoreDefaults: String { pick("Restore defaults", "R\u{e9}tablir les valeurs par d\u{e9}faut") }
    public var emptyDictionary: String {
        pick("No words yet. Words you add from a suggestion card appear here.",
             "Aucun mot pour l\u{2019}instant. Les mots ajout\u{e9}s depuis une carte appara\u{ee}tront ici.")
    }
    public var emptyMutedRules: String {
        pick("No rules muted. Rules you mute from a suggestion card appear here.",
             "Aucune r\u{e8}gle masqu\u{e9}e. Les r\u{e8}gles masqu\u{e9}es depuis une carte appara\u{ee}tront ici.")
    }
    public var unmute: String          { pick("Unmute", "R\u{e9}afficher") }

    public var blockedApplications: String {
        pick("Never correct in these applications", "Ne jamais corriger dans ces applications")
    }
    public var blockedApplicationsHelp: String {
        pick("\u{2325}\u{2318}C refuses to act in these. Password fields are always refused, everywhere.",
             "\u{2325}\u{2318}C refuse d\u{2019}agir dans celles-ci. Les champs de mot de passe sont toujours refus\u{e9}s, partout.")
    }
    public var addApplication: String  { pick("Bundle identifier\u{2026}", "Identifiant de bundle\u{2026}") }
    public var invalidBundleIdentifier: String {
        pick("That does not look like a bundle identifier \u{2014} try com.apple.Terminal",
             "Cela ne ressemble pas \u{e0} un identifiant de bundle \u{2014} essayez com.apple.Terminal")
    }
    public var shippedProtectionWarning: String {
        pick("This one ships blocked for a reason: a shell runs what it is given.",
             "Celle-ci est bloqu\u{e9}e par d\u{e9}faut pour une raison : un terminal ex\u{e9}cute ce qu\u{2019}on lui donne.")
    }

    // Updates
    public var checkForUpdates: String { pick("Check for Updates\u{2026}", "Rechercher des mises \u{e0} jour\u{2026}") }
    public var automaticUpdates: String {
        pick("Check for updates automatically", "Rechercher les mises \u{e0} jour automatiquement")
    }
    /// Shown when the build has no feed or no public key, which is the state
    /// of any build made before the release keys exist.
    public var updatesNotConfigured: String {
        pick("This build has no update feed.", "Cette version n\u{2019}a pas de flux de mise \u{e0} jour.")
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
