import Foundation

/// Formatting attributes carried by an operation.
///
/// Quill's own attribute model is richer (nested values); Corrector
/// models attributes as a flat string map, which covers the formatting the
/// check engine produces while staying `Codable` and `Hashable` for free.
public typealias Attributes = [String: String]

/// A single Quill-Delta style operation.
///
/// Mirrors the Quill Delta operation vocabulary
///: exactly three cases, lengths measured in UTF-16 code units.
public enum Op: Equatable, Hashable, Codable, Sendable {
    case insert(String, Attributes? = nil)
    case retain(Int, Attributes? = nil)
    case delete(Int)

    /// Length of the operation in UTF-16 code units.
    public var length: Int {
        switch self {
        case.insert(let text, _): return text.utf16Length
        case.retain(let n, _): return n
        case.delete(let n): return n
        }
    }

    public var attributes: Attributes? {
        switch self {
        case.insert(_, let a), .retain(_, let a): return a
        case.delete: return nil
        }
    }

    public var isInsert: Bool { if case.insert = self { return true }; return false }
    public var isRetain: Bool { if case.retain = self { return true }; return false }
    public var isDelete: Bool { if case.delete = self { return true }; return false }

    /// The first `n` code units of this operation.
    func prefix(_ n: Int) -> Op {
        switch self {
        case.insert(let text, let a): return .insert(text.utf16Slice(from: 0, length: n), a)
        case.retain(_, let a): return .retain(n, a)
        case.delete: return .delete(n)
        }
    }

    /// Everything after the first `n` code units.
    func suffix(_ n: Int) -> Op {
        switch self {
        case.insert(let text, let a):
            return .insert(text.utf16Slice(from: n, length: text.utf16Length - n), a)
        case.retain(let len, let a): return .retain(len - n, a)
        case.delete(let len): return .delete(len - n)
        }
    }
}

// MARK: - Attribute algebra

enum Attr {
    /// Result of applying `b` on top of `a`.
    /// With `keepNull == false`, attributes set to the sentinel are dropped.
    static func compose(_ a: Attributes?, _ b: Attributes?, keepNull: Bool) -> Attributes? {
        let base = a ?? [:]
        let top = b ?? [:]
        var out = top.merging(base) { new, _ in new }
        if !keepNull { out = out.filter { $0.value != Attributes.nullSentinel } }
        return out.isEmpty ? nil : out
    }

    /// `b` rebased over a concurrent `a`. `priority == true` means `a` wins ties.
    static func transform(_ a: Attributes?, _ b: Attributes?, priority: Bool) -> Attributes? {
        guard let a, !a.isEmpty else { return (b?.isEmpty ?? true) ? nil : b }
        guard let b, !b.isEmpty else { return nil }
        if !priority { return b }
        let out = b.filter { a[$0.key] == nil }
        return out.isEmpty ? nil : out
    }

    /// Attributes that undo `applied` given `base`.
    static func invert(_ applied: Attributes?, base: Attributes?) -> Attributes? {
        let applied = applied ?? [:]
        let base = base ?? [:]
        var out: Attributes = [:]
        for (k, v) in base where applied[k] != v {
            out[k] = v
        }
        for k in applied.keys where base[k] == nil {
            out[k] = Attributes.nullSentinel
        }
        return out.isEmpty ? nil : out
    }
}

public extension Dictionary where Key == String, Value == String {
    /// Marker meaning "remove this attribute" — Delta has no native null in a
    /// `[String: String]` map, so a reserved value stands in for it.
    static var nullSentinel: String { "\u{0}__null__" }
}
