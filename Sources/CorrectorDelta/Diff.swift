import Foundation

/// Text differencing used to turn "the document changed" into a changeset.
///
/// Pluggable because the right answer depends on the edit: trimming the shared
/// prefix and suffix is almost free and exactly right for someone typing, while
/// a word-level LCS costs more and earns it when a block has been rewritten.
/// Both ship; the caller picks.
public protocol DiffStrategy: Sendable {
    func diff(from old: String, to new: String) -> Delta
}

/// Trims the shared prefix and suffix, then replaces the middle.
///
/// Cheap and allocation-light, which is what a per-keystroke path wants.
public struct AffixDiffStrategy: DiffStrategy {
    public init() {}

    public func diff(from old: String, to new: String) -> Delta {
        let a = Array(old.utf16), b = Array(new.utf16)
        if a == b { return Delta() }

        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }

        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix,
              a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }

        let removed = a.count - prefix - suffix
        let insertedUnits = Array(b[prefix..<(b.count - suffix)])

        var delta = Delta()
        if prefix > 0 { delta.retain(prefix) }
        if removed > 0 { delta.delete(removed) }
        if !insertedUnits.isEmpty {
            delta.insert(String(utf16CodeUnits: insertedUnits, count: insertedUnits.count))
        }
        return delta.chop()
    }
}

/// Word-level longest-common-subsequence diff.
///
/// Produces changesets that align to word boundaries, which keeps suggestion
/// spans stable while a user edits inside a sentence. Costs O(n·m) on word
/// counts, so it is used for whole-document reconciliation, not per keystroke.
public struct WordLCSDiffStrategy: DiffStrategy {
    public init() {}

    public func diff(from old: String, to new: String) -> Delta {
        if old == new { return Delta() }
        let a = Self.tokenize(old), b = Self.tokenize(new)
        guard !a.isEmpty, !b.isEmpty else { return AffixDiffStrategy().diff(from: old, to: new) }

        var table = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var delta = Delta()
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                delta.retain(a[i].utf16Length); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                delta.delete(a[i].utf16Length); i += 1
            } else {
                delta.insert(b[j]); j += 1
            }
        }
        while i < a.count { delta.delete(a[i].utf16Length); i += 1 }
        while j < b.count { delta.insert(b[j]); j += 1 }
        return delta.chop()
    }

    /// Split into words and the runs of whitespace between them, so that
    /// reassembling the tokens reproduces the input exactly.
    static func tokenize(_ s: String) -> [String] {
        var out: [String] = []
        var current = ""
        var currentIsSpace: Bool?
        for ch in s {
            let isSpace = ch.isWhitespace
            if currentIsSpace == nil || currentIsSpace == isSpace {
                current.append(ch)
            } else {
                out.append(current); current = String(ch)
            }
            currentIsSpace = isSpace
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
