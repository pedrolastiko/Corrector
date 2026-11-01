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
    public static let version = "0.5.1"

    /// Pre-release stage. Empty once there is nothing to qualify.
    public static let stage = "beta"

    /// "beta 0.5.1" — what the footer shows.
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
             english: "A button in the toolbar clears the document, next to "
                    + "Copy. It is disabled while the document is already "
                    + "empty.",
             french: "Un bouton dans la barre d’outils efface le document, "
                   + "à côté de Copier. Il est désactivé quand le document "
                   + "est déjà vide."),
        Note(id: 2, kind: .feature,
             english: "That clear can be taken back for thirty seconds: the "
                    + "same button turns into an undo arrow and puts the text "
                    + "back. Nothing else reaches it — ⌘Z does not undo a "
                    + "clear.",
             french: "Cet effacement se reprend pendant trente secondes : le "
                   + "même bouton devient une flèche de retour et remet le "
                   + "texte. Rien d’autre ne le rattrape — ⌘Z n’annule pas un "
                   + "effacement."),
        Note(id: 3, kind: .feature,
             english: "Corrector can open at login, from the menu-bar menu. "
                    + "macOS keeps the switch in System Settings > General > "
                    + "Login Items, so it can be revoked without the app "
                    + "running.",
             french: "Corrector peut s’ouvrir au démarrage, depuis le menu de "
                   + "la barre de menus. macOS conserve le réglage dans "
                   + "Réglages > Général > Ouverture, où il peut être révoqué "
                   + "sans lancer l’application."),
    ]
}
