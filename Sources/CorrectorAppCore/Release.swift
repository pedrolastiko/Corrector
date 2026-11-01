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
    public static let version = "5.1.2"

    /// Pre-release stage. Empty once there is nothing to qualify.
    public static let stage = "beta"

    /// "beta 5.1.2" — what the footer shows.
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
             english: "A settings window, at \u{2318},. The personal "
                    + "dictionary, the muted rules and the applications the "
                    + "shortcut skips can all be read and changed there \u{2014} "
                    + "until now they could only be written.",
             french: "Une fen\u{ea}tre de r\u{e9}glages, par \u{2318},. Le dictionnaire "
                   + "personnel, les r\u{e8}gles masqu\u{e9}es et les applications que "
                   + "le raccourci ignore s\u{2019}y lisent et s\u{2019}y modifient \u{2014} "
                   + "jusqu\u{2019}ici on ne pouvait que les y \u{e9}crire."),
        Note(id: 2, kind: .feature,
             english: "Corrector can update itself. Builds carrying an update "
                    + "feed check for new versions and install them; builds "
                    + "without one say so instead of pretending.",
             french: "Corrector peut se mettre \u{e0} jour. Les versions dot\u{e9}es "
                   + "d\u{2019}un flux cherchent les nouveaut\u{e9}s et les installent ; "
                   + "celles qui n\u{2019}en ont pas le disent au lieu de faire "
                   + "semblant."),
        Note(id: 3, kind: .fix,
             english: "Adding a word to the dictionary or muting a rule is no "
                    + "longer a one-way door: both can be undone from the "
                    + "settings window.",
             french: "Ajouter un mot au dictionnaire ou masquer une r\u{e8}gle "
                   + "n\u{2019}est plus sans retour : les deux se d\u{e9}font depuis la "
                   + "fen\u{ea}tre de r\u{e9}glages."),
    ]
}
