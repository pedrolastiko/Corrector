import Foundation
import CorrectorCore
import CorrectorEngine
import CorrectorDelta

/// Session lifecycle states.
///
/// An explicit finite state machine, so an invalid transition — a changeset
/// submitted before the session started — comes back as an error rather than a
/// crash or a silently dropped message.
public enum SessionState: Equatable, Sendable {
    case idle
    case starting
    case active
    case finished
    case failed(SessionError)
}

/// A checking session over one document.
///
/// Implements the core of the editing workflow:
/// handshake with capability negotiation, changeset submission, alert
/// production stamped with a revision, rebasing stale alerts onto the current
/// revision, and user actions feeding back into the store.
public final class CheckSession {
    public private(set) var state: SessionState = .idle
    public private(set) var sessionUUID: UUID?
    public private(set) var allowedFeatures: FeatureSet = []
    public private(set) var maxMessageSize: Int = 64 * 1024

    public let editSession: InMemoryEditSession
    public let alertStore = AlertStore()

    private let engine: CheckEngine
    private var dialect: Dialect = .american
    private var documentIdentifier: String = ""

    /// The language the last check actually ran in, after `auto` resolved.
    public private(set) var language: Language = .english

    /// Detection result, frozen for the life of the session.
    ///
    /// Re-detecting on every pass let the language flip mid-edit: applying a
    /// French elision shortened the text just enough for the next pass to
    /// decide it was English, which then applied English punctuation rules to
    /// French text. A document does not change language while being edited, so
    /// this is resolved once and kept.
    private var lockedDialect: Dialect?

    /// Revision the currently held alerts were computed against.
    public private(set) var checkedRevision: Int = -1

    public init(engine: CheckEngine = CheckEngine(), text: String = "") {
        self.engine = engine
        self.editSession = InMemoryEditSession(text: text)
    }

    public var text: String { editSession.text }
    public var revision: Int { editSession.revision }

    // MARK: - Message handling

    @discardableResult
    public func handle(_ message: ClientMessage) -> [ServerMessage] {
        switch message {
        case.startSession(let request):
            return start(request)

        case.submitChangeset(_, let revision, let changeSet):
            return submit(changeSet: changeSet, atRevision: revision)

        case.toggleChecks(let features):
            engine.features = features.intersection(allowedFeatures)
            return recheck()

        case.userAction(let alertID, let action):
            return apply(action: action, to: alertID)

        case.requestTextStats:
            return [.textInfo(TextStats.compute(for: text, language: language))]

        case.ping:
            return [.pong]
        }
    }

    private func start(_ request: ClientMessage.StartSession) -> [ServerMessage] {
        guard state == .idle else {
            state = .failed(.alreadyStarted)
            return [.error(.alreadyStarted)]
        }
        state = .starting
        dialect = request.dialect
        documentIdentifier = request.documentIdentifier

        // Capability negotiation: the session grants a subset of what the
        // caller advertised. A transient field gets correctness checks only —
        // nobody wants tone advice on a search box.
        let serviceSupports: FeatureSet = request.documentIdentifierIsTransient
            ? .correctnessOnly : .all
        allowedFeatures = request.clientSupports.intersection(serviceSupports)
        engine.features = allowedFeatures

        let uuid = UUID()
        sessionUUID = uuid
        state = .active

        var messages: [ServerMessage] = [
            .started(.init(sessionUUID: uuid,
                           allowedFeatures: allowedFeatures,
                           maxMessageSize: maxMessageSize))
        ]

        if !request.text.isEmpty {
            var seed = Delta()
            seed.insert(request.text)
            _ = try? editSession.applyDelta(seed)
        }
        messages.append(contentsOf: recheck())
        return messages
    }

    private func submit(changeSet: Delta, atRevision revision: Int) -> [ServerMessage] {
        guard state == .active else { return [.error(.notStarted)] }

        // Message size limiting: a paste of a whole book is a changeset like
        // any other, and refusing it with an error beats freezing the UI.
        let size = changeSet.ops.reduce(0) { $0 + max($1.length, 1) }
        guard size <= maxMessageSize else {
            return [.error(.messageTooLarge(size: size, limit: maxMessageSize))]
        }
        guard revision == editSession.revision else {
            return [.error(.staleRevision(expected: editSession.revision, received: revision))]
        }

        guard (try? editSession.applyDelta(changeSet)) != nil else {
            return [.error(.notStarted)]
        }

        // Rebase the alerts we already hold onto the new revision before
        // rechecking, so cards that survive keep their identity and position
        //.
        alertStore.rebase(through: changeSet, newRevision: editSession.revision)
        return recheck()
    }

    /// Run the engine and merge the result into the store.
    @discardableResult
    public func recheck() -> [ServerMessage] {
        let result = engine.check(text: text, revision: editSession.revision,
                                  dialect: resolveDialect())
        let diff = alertStore.apply(incoming: result.alerts, revision: editSession.revision)
        checkedRevision = editSession.revision
        language = result.language

        var messages: [ServerMessage] = []
        if !diff.isEmpty {
            messages.append(.alertChanges(diff, revision: editSession.revision))
        }
        messages.append(.finished(.init(
            revision: editSession.revision,
            scores: result.scores,
            stats: result.stats,
            removed: diff.removed,
            foreign: false)))
        return messages
    }

    /// The dialect this session checks in, detecting once if it was `auto`.
    private func resolveDialect() -> Dialect {
        guard dialect == .auto else { return dialect }
        if let locked = lockedDialect { return locked }

        let detected = Dialect.default(for: LanguageDetector.detect(in: text))
        // Freeze only once there is enough text for detection to be stable;
        // before that, keep re-asking so an empty document that is typed into
        // still lands on the right language.
        let substantial = Tokenizer.words(in: text, language: .french)
            .filter { $0.text.count > 1 }.count >= 4
        if substantial { lockedDialect = detected }
        return detected
    }

    private func apply(action: ClientMessage.UserAction, to alertID: Int) -> [ServerMessage] {
        guard state == .active else { return [.error(.notStarted)] }
        guard let alert = alertStore.alert(id: alertID) else { return [] }

        switch action {
        case.insert:
            // Accept: apply the replacement, then recheck.
            guard let delta = alert.applyDelta(documentLength: editSession.document.length),
                  (try? editSession.applyDelta(delta)) != nil else { return [] }
            alertStore.rebase(through: delta, newRevision: editSession.revision)
            alertStore.remove(id: alertID)
            return [.removeAlert(id: alertID)] + recheck()

        case.dismiss, .skip:
            alertStore.remove(id: alertID)
            return [.removeAlert(id: alertID)]

        case.offensive:
            alertStore.mute(rule: alert.pname)
            return recheck()

        case.view, .hover, .open, .click, .copy, .next:
            alertStore.select(id: alertID)
            return []
        }
    }

    // MARK: - Convenience

    /// Type `text` at the caret and recheck — the path a keystroke takes.
    @discardableResult
    public func type(_ newText: String) -> [ServerMessage] {
        let caret = editSession.selection
        var delta = Delta()
        if caret.begin > 0 { delta.retain(caret.begin) }
        if caret.end > caret.begin { delta.delete(caret.end - caret.begin) }
        delta.insert(newText)
        return handle(.submitChangeset(id: 0, revision: editSession.revision,
                                       changeSet: delta.chop()))
    }

    /// Replace the whole document, diffing to a changeset first.
    @discardableResult
    public func replaceAll(with newText: String,
                           strategy: DiffStrategy = WordLCSDiffStrategy()) -> [ServerMessage] {
        let delta = strategy.diff(from: text, to: newText)
        guard !delta.isEmpty else { return [] }
        return handle(.submitChangeset(id: 0, revision: editSession.revision, changeSet: delta))
    }

    /// Accept a suggestion by id.
    @discardableResult
    public func accept(alertID: Int) -> [ServerMessage] {
        handle(.userAction(alertID: alertID, action: .insert))
    }

    /// Accept every held suggestion that has a replacement, highest priority
    /// first. Re-resolves ids each round because accepting one shifts the rest.
    @discardableResult
    public func acceptAll() -> Int {
        var applied = 0
        var guardCount = 0
        while guardCount < 500 {
            guardCount += 1
            guard let next = alertStore.visibleAlerts.first(where: { !$0.replacements.isEmpty })
            else { break }
            _ = accept(alertID: next.id)
            applied += 1
        }
        return applied
    }
}
