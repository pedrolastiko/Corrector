import Foundation

/// Cursor over a list of operations that can yield partial operations.
///
/// Counterpart of Quill Delta's operation iterator. `compose`,
/// `transform` and `diff` all advance two of these in lockstep, consuming
/// `min(peekLength, peekLength)` at a time.
struct OpIterator {
    private let ops: [Op]
    private var index = 0
    private var offset = 0

    init(_ ops: [Op]) { self.ops = ops }

    var hasNext: Bool { peekLength < Int.max }

    /// Length remaining in the current operation, or `Int.max` when exhausted.
    var peekLength: Int {
        guard index < ops.count else { return .max }
        return ops[index].length - offset
    }

    /// Type of the current operation; `.retain` once exhausted so that trailing
    /// retains are implied rather than required.
    var peekType: Op {
        guard index < ops.count else { return .retain(Int.max) }
        return ops[index]
    }

    /// Consume up to `length` code units, returning the slice consumed.
    mutating func next(_ length: Int = .max) -> Op {
        guard index < ops.count else {
            return .retain(length == .max ? Int.max : length)
        }
        let op = ops[index]
        let remaining = op.length - offset
        let take = min(length, remaining)
        let slice = (offset == 0 && take == op.length) ? op : op.suffix(offset).prefix(take)
        if take == remaining {
            index += 1
            offset = 0
        } else {
            offset += take
        }
        return slice
    }
}
