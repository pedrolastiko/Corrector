import Foundation
import CryptoKit
import CorrectorDelta

/// Stable identity for an editing surface.
///
/// A 64-hex SHA-256 digest of a description of the *field* — application,
/// window, field — rather than of its contents. That is what lets Corrector
/// recognise "the same text box" across relaunches without ever persisting the
/// user's text, and it keeps the id stable while the text changes.
public struct DocumentID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: String
    public init(value: String) { self.value = value }

    /// Derive an id by hashing a stable description of the surface.
    public static func derive(application: String, window: String, field: String) -> DocumentID {
        let seed = "\(application)\u{1F}\(window)\u{1F}\(field)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return DocumentID(value: digest.map { String(format: "%02x", $0) }.joined())
    }

    public var description: String { value }
    public var short: String { String(value.prefix(12)) }
}

/// A persisted document plus how far it has been acknowledged.
public struct StoredDocument: Codable, Equatable, Sendable {
    public var documentID: String
    public var text: String
    public var revision: Int
    /// The revision the suggestions were last computed against, so a document
    /// reopened mid-edit knows whether its alerts are stale.
    public var lastSyncedRevision: Int?
    public var updatedAt: Date

    public init(documentID: String, text: String, revision: Int,
                lastSyncedRevision: Int? = nil, updatedAt: Date = Date()) {
        self.documentID = documentID
        self.text = text
        self.revision = revision
        self.lastSyncedRevision = lastSyncedRevision
        self.updatedAt = updatedAt
    }
}

/// Dependency-free JSON persistence for documents and user preferences.
///
/// JSON rather than SQLite: the data is a handful of documents and a
/// preference set, read once at launch and written on change. A database would
/// add a dependency, a migration story and a schema to the build in exchange
/// for queries nothing here performs.
///
/// A TTL cache was built here first and then removed — nothing in an offline
/// checker goes stale, so it was tested code that no caller could reach.
public final class DocumentStore {
    private let root: URL
    private let fileManager = FileManager.default

    public init(root: URL) throws {
        self.root = root
        try fileManager.createDirectory(at: root.appendingPathComponent("documents"),
                                        withIntermediateDirectories: true)

    }

    /// A store under the user's caches directory.
    public static func defaultStore() throws -> DocumentStore {
        let base = fileManager_cachesURL().appendingPathComponent("Corrector", isDirectory: true)
        return try DocumentStore(root: base)
    }

    private static func fileManager_cachesURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private func documentURL(_ id: DocumentID) -> URL {
        root.appendingPathComponent("documents/\(id.value).json")
    }

    // MARK: - Documents

    public func save(_ document: StoredDocument) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: documentURL(DocumentID(value: document.documentID)),
                                           options: .atomic)
    }

    public func load(_ id: DocumentID) throws -> StoredDocument? {
        let url = documentURL(id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredDocument.self, from: Data(contentsOf: url))
    }

    /// Record that the checker has consumed up to `revision`.
    public func checkpoint(_ id: DocumentID, syncedRevision: Int) throws {
        guard var document = try load(id) else { return }
        document.lastSyncedRevision = syncedRevision
        document.updatedAt = Date()
        try save(document)
    }

    public func allDocuments() throws -> [StoredDocument] {
        let dir = root.appendingPathComponent("documents")
        let urls = (try? fileManager.contentsOfDirectory(at: dir,
                                                         includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return urls
            .filter { $0.pathExtension == "json" }
                .compactMap { try? decoder.decode(StoredDocument.self, from: Data(contentsOf: $0)) }
                    .sorted { $0.updatedAt > $1.updatedAt }
    }

}
