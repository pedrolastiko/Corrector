import Foundation
import CorrectorSession

/// What this build is, and what changed in it.
///
/// One place, so the footer, the handshake’s `clientVersion` and the bundle’s
/// `CFBundleShortVersionString` cannot drift apart — which they had already
/// begun to do: the protocol constant said 1.0.0 while the work was plainly
/// pre-release.
public enum Release {

    /// The marketing version: what a person reads.
    public static let version = "0.5"

    /// Pre-release stage. Empty once there is nothing to qualify.
    public static let stage = "beta"

    /// "beta 0.5" — what the footer shows.
    public static var display: String {
        stage.isEmpty ? version : "\(stage) \(version)"
    }

    /// The same build, as the handshake reports it.
    public static var protocolVersion: String { CorrectorVersion.current }

    // MARK: - Release notes

    public enum Change: String, Sendable {
        case feature
        case fix

        /// A glyph rather than a word, so the two read as one list.
        public var symbol: String {
            switch self {
            case .feature: return "sparkles"
            case .fix: return "wrench.adjustable"
            }
        }
    }

    public struct Note: Identifiable, Sendable {
        public let id: Int
        public let kind: Change
        let english: String
        let french: String

        public func text(_ locale: UILocale) -> String {
            locale == .french ? french : english
        }
    }

    /// What changed in this build, newest first.
    ///
    /// Written for someone deciding whether the change affects them, not as a
    /// commit list. Each line names the behaviour, not the type that
    /// implements it.
    public static let notes: [Note] = [
        Note(id: 1, kind: .feature,
             english: "The ⌥⌘C shortcut now replaces text through the "
                    + "Accessibility API where it can, leaving your clipboard "
                    + "untouched and the host application’s undo intact.",
             french: "Le raccourci ⌥⌘C remplace désormais le texte via l’API "
                   + "d’accessibilité quand c’est possible, sans toucher à "
                   + "votre presse-papiers ni à l’annulation de l’application."),
        Note(id: 2, kind: .feature,
             english: "The shortcut refuses to act in password fields, "
                    + "terminals and password managers.",
             french: "Le raccourci refuse d’agir dans les champs de mot de "
                   + "passe, les terminaux et les gestionnaires de mots de passe."),
        Note(id: 3, kind: .feature,
             english: "The shortcut applies spelling and punctuation only. "
                    + "Grammar and style stay in the window and the right-click "
                    + "menu, where you can see what they changed.",
             french: "Le raccourci n’applique que l’orthographe et la "
                   + "ponctuation. La grammaire et le style restent dans la "
                   + "fenêtre et le menu contextuel, où vous voyez ce qui change."),
        Note(id: 4, kind: .fix,
             english: "Correcting a selection no longer capitalises it or adds "
                    + "a full stop: a selection is a fragment, not a sentence.",
             french: "Corriger une sélection n’y ajoute plus de majuscule ni de "
                   + "point final : une sélection est un fragment, pas une phrase."),
        Note(id: 5, kind: .fix,
             english: "The dialect you choose is now actually used for "
                    + "spelling. British, Canadian, Australian and Indian "
                    + "English all shared the American dictionary before.",
             french: "Le dialecte choisi est enfin utilisé pour l’orthographe. "
                   + "L’anglais britannique, canadien, australien et indien "
                   + "partageaient jusqu’ici le dictionnaire américain."),
        Note(id: 6, kind: .fix,
             english: "If a regional dictionary is not installed, checking "
                    + "falls back to the base language instead of silently "
                    + "finding no mistakes at all.",
             french: "Si un dictionnaire régional n’est pas installé, la "
                   + "vérification retombe sur la langue de base au lieu de ne "
                   + "silencieusement plus rien trouver."),
    ]
}
