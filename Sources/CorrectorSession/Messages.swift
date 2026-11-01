import Foundation
import CorrectorCore
import CorrectorEngine
import CorrectorDelta

/// Messages sent from the client to the checking service.
///
/// A message vocabulary — session start, changeset submission, check toggling,
/// feedback, statistics — rather than direct method calls. It all runs
/// in-process today; modelling it as messages is what keeps the engine
/// reachable from somewhere other than the window without a rewrite.
public enum ClientMessage: Equatable, Sendable {
    /// Opens a session and negotiates capabilities.
    case startSession(StartSession)
    /// Submits a changeset against a revision.
    case submitChangeset(id: Int, revision: Int, changeSet: Delta)
    /// `ToggleChecksMessage`.
    case toggleChecks(FeatureSet)
    /// Reports what the user did with a suggestion.
    case userAction(alertID: Int, action: UserAction)
    /// `GetTextStatsRequestMessage`.
    case requestTextStats
    /// Keepalive.
    case ping

    public struct StartSession: Equatable, Sendable {
        public var clientName: String
        public var clientVersion: String
        /// What the caller is willing to run. The session answers with what it
        /// will actually allow, which is always a subset.
        public var clientSupports: FeatureSet
        public var dialect: Dialect
        public var documentIdentifier: String
        /// An ephemeral field rather than a document worth persisting — a
        /// search box, a one-line form. Narrows the check set and skips the
        /// store entirely.
        public var documentIdentifierIsTransient: Bool
        /// Where the typing is happening. Suggestions reasonable in a document
        /// are not reasonable in a chat box.
        public var application: String
        public var domain: String
        public var text: String

        public init(clientName: String = "Corrector",
                    clientVersion: String = CorrectorVersion.current,
                    clientSupports: FeatureSet = .all,
                    dialect: Dialect = .american,
                    documentIdentifier: String,
                    documentIdentifierIsTransient: Bool = false,
                    application: String = "cli",
                    domain: String = "general",
                    text: String = "") {
            self.clientName = clientName
            self.clientVersion = clientVersion
            self.clientSupports = clientSupports
            self.dialect = dialect
            self.documentIdentifier = documentIdentifier
            self.documentIdentifierIsTransient = documentIdentifierIsTransient
            self.application = application
            self.domain = domain
            self.text = text
        }
    }

    /// What the user did with a suggestion, so a rule that is always dismissed
    /// can be found and fixed rather than guessed at.
    public enum UserAction: String, Sendable {
        case view, hover, open, click, insert, dismiss, skip, copy, next, offensive
    }
}

/// Messages sent from the checking service back to the client.
public enum ServerMessage: Equatable, Sendable {
    /// Answers the handshake with the granted capabilities.
    case started(Started)
    /// `AlertChangesMessage` — a batch of new or updated suggestions.
    case alertChanges(AlertDiff, revision: Int)
    /// `RemoveAlertMessage`.
    case removeAlert(id: Int)
    /// Closes a check pass with scores and statistics.
    case finished(Finished)
    /// `TextCheckInfo`.
    case textInfo(TextStats)
    /// `ErrorMessage`.
    case error(SessionError)
    case pong

    public struct Started: Equatable, Sendable {
        public var sessionUUID: UUID
        /// What the session will actually run — always a subset of what the
        /// caller advertised.
        public var allowedFeatures: FeatureSet
        public var maxMessageSize: Int
        public init(sessionUUID: UUID, allowedFeatures: FeatureSet, maxMessageSize: Int) {
            self.sessionUUID = sessionUUID
            self.allowedFeatures = allowedFeatures
            self.maxMessageSize = maxMessageSize
        }
    }

    public struct Finished: Equatable, Sendable {
        public var revision: Int
        public var scores: Scores
        public var stats: TextStats
        public var removed: [Int]
        /// Set when the text is not in the session's language.
        public var foreign: Bool
    }
}

public enum SessionError: Error, Equatable, Sendable {
    case notStarted
    case alreadyStarted
    case staleRevision(expected: Int, received: Int)
    case messageTooLarge(size: Int, limit: Int)
}

public enum CorrectorVersion {
    /// Sent as `clientVersion` in the handshake. `Release` in the app layer
    /// reads this rather than carrying its own copy.
    public static let current = "0.5.1-beta"
}
