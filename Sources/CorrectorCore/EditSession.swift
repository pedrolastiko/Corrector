import Foundation
import CorrectorDelta

/// What the host text field can actually do.
///
/// Text fields are not interchangeable: a chat composer, a password field and
/// a browser-hosted document differ in what they will let anything do to them.
/// Asking before offering an action is the difference between an action that
/// fails silently and one that is never offered.
public struct DocumentCapabilities: OptionSet, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let readText       = DocumentCapabilities(rawValue: 1 << 0)
    public static let replaceRange   = DocumentCapabilities(rawValue: 1 << 1)
    public static let insertAtCaret  = DocumentCapabilities(rawValue: 1 << 2)
    public static let setSelection   = DocumentCapabilities(rawValue: 1 << 3)
    public static let richText       = DocumentCapabilities(rawValue: 1 << 4)

    public static let plainEditable: DocumentCapabilities =
        [.readText, .replaceRange, .insertAtCaret, .setSelection]
    public static let readOnly: DocumentCapabilities = [.readText]
}

/// A selected range, in UTF-16 code units.
public struct Selection: Equatable, Codable, Sendable {
    public var begin: Int
    public var end: Int
    public init(begin: Int, end: Int) { self.begin = begin; self.end = end }
    public var isCaret: Bool { begin == end }
}

/// A snapshot of the document at a revision.
public struct DocumentState: Equatable, Sendable {
    public var text: String
    public var revision: Int
    public var selection: Selection
    public init(text: String, revision: Int, selection: Selection) {
        self.text = text; self.revision = revision; self.selection = selection
    }
}

public enum EditSessionError: Error, Equatable {
    case unsupported(DocumentCapabilities)
    case rangeOutOfBounds
}

/// The host interface an editing surface exposes.
///
/// Deliberately small — read the state, replace a range, move the selection,
/// copy. `InMemoryEditSession` is the only implementation that ships; keeping
/// the verb set this narrow is what makes the engine testable without a
/// window.
public protocol EditSession: AnyObject {
    var capabilities: DocumentCapabilities { get }
    func getDocumentState() -> DocumentState
    func applyDelta(_ delta: Delta) throws -> DocumentState
    func insertText(_ text: String, at range: Selection) throws -> DocumentState
    func insertAtCaret(_ text: String) throws -> DocumentState
    func setSelection(_ selection: Selection) throws
    func copyText(range: Selection) throws -> String
}

/// An in-memory editing surface.
///
/// Keeps a document delta and a monotonically increasing revision: every
/// mutation bumps the revision and yields a changeset, which is what lets a
/// suggestion computed against an older revision be rebased onto the current
/// text instead of thrown away.
public final class InMemoryEditSession: EditSession {
    public private(set) var document: Delta
    public private(set) var revision: Int
    public private(set) var selection: Selection
    public let capabilities: DocumentCapabilities

    /// Every changeset applied, newest last — the local OT log.
    public private(set) var history: [Delta] = []

    public init(text: String = "",
                capabilities: DocumentCapabilities = .plainEditable) {
        self.document = Delta(text: text)
        self.revision = 0
        self.selection = Selection(begin: 0, end: 0)
        self.capabilities = capabilities
    }

    public var text: String { document.text }

    public func getDocumentState() -> DocumentState {
        DocumentState(text: document.text, revision: revision, selection: selection)
    }

    @discardableResult
    public func applyDelta(_ delta: Delta) throws -> DocumentState {
        guard capabilities.contains(.replaceRange) else {
            throw EditSessionError.unsupported(.replaceRange)
        }
        document = document.compose(delta)
        history.append(delta)
        revision += 1
        selection = Selection(begin: delta.transformCursorPosition(selection.begin),
                              end: delta.transformCursorPosition(selection.end))
        return getDocumentState()
    }

    @discardableResult
    public func insertText(_ text: String, at range: Selection) throws -> DocumentState {
        guard capabilities.contains(.replaceRange) else {
            throw EditSessionError.unsupported(.replaceRange)
        }
        let length = document.length
        guard range.begin >= 0, range.end >= range.begin, range.end <= length else {
            throw EditSessionError.rangeOutOfBounds
        }
        var delta = Delta()
        if range.begin > 0 { delta.retain(range.begin) }
        if range.end > range.begin { delta.delete(range.end - range.begin) }
        if !text.isEmpty { delta.insert(text) }
        return try applyDelta(delta.chop())
    }

    @discardableResult
    public func insertAtCaret(_ text: String) throws -> DocumentState {
        guard capabilities.contains(.insertAtCaret) else {
            throw EditSessionError.unsupported(.insertAtCaret)
        }
        return try insertText(text, at: selection)
    }

    public func setSelection(_ selection: Selection) throws {
        guard capabilities.contains(.setSelection) else {
            throw EditSessionError.unsupported(.setSelection)
        }
        let length = document.length
        guard selection.begin >= 0, selection.end >= selection.begin,
              selection.end <= length else { throw EditSessionError.rangeOutOfBounds }
        self.selection = selection
    }

    public func copyText(range: Selection) throws -> String {
        guard capabilities.contains(.readText) else {
            throw EditSessionError.unsupported(.readText)
        }
        return document.text.utf16Slice(range.begin, range.end)
    }

    /// Composition of every changeset applied since `revision`.
    ///
    /// This is what an alert computed at an older revision must be rebased
    /// through before it can be displayed.
    public func changesSince(revision oldRevision: Int) -> Delta {
        guard oldRevision < revision else { return Delta() }
        let start = max(0, history.count - (revision - oldRevision))
        return history[start...].reduce(Delta()) { $0.compose($1) }
    }
}
