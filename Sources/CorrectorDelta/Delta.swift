import Foundation

/// An ordered sequence of `insert` / `retain` / `delete` operations describing
/// either a document (inserts only) or a change to one.
///
/// An implementation of the Quill Delta model, written from its published
/// specification. The operation set and the `compose` / `transform` / `invert`
/// triple come from that algebra: it is the standard answer to anchoring
/// annotations in text that is being edited underneath them.
public struct Delta: Equatable, Hashable, Codable, Sendable {
    public private(set) var ops: [Op]

    public init(_ ops: [Op] = []) {
        self.ops = []
        for op in ops { push(op) }
    }

    /// Build a document delta from plain text.
    public init(text: String) {
        self.ops = text.isEmpty ? [] : [.insert(text)]
    }

    public var isEmpty: Bool { ops.isEmpty }

    /// Total length in UTF-16 code units, counting every operation.
    public var length: Int { ops.reduce(0) { $0 + $1.length } }

    /// Net change in document length this delta produces.
    public var changeLength: Int {
        ops.reduce(0) { total, op in
            switch op {
            case.insert(let t, _): return total + t.utf16Length
            case.delete(let n): return total - n
            case.retain: return total
            }
        }
    }

    /// Concatenated text of all `insert` operations — the document content.
    public var text: String {
        ops.reduce(into: "") { acc, op in
            if case.insert(let t, _) = op { acc += t }
        }
    }

    // MARK: - Building

    /// Append an operation, merging it with the previous one where possible so
    /// the delta stays in canonical form.
    public mutating func push(_ op: Op) {
        if op.length == 0, !op.isInsert { return }
        if case.insert(let t, _) = op, t.isEmpty { return }

        guard var last = ops.last else { ops.append(op); return }

        // A delete immediately followed by an insert is normalised to
        // insert-then-delete, so that equal deltas compare equal.
        if last.isDelete, op.isInsert {
            ops.removeLast()
            if let prior = ops.last, prior.isInsert, case.insert(let a, let aAttr) = prior,
               case.insert(let b, let bAttr) = op, aAttr == bAttr {
                ops[ops.count - 1] = .insert(a + b, aAttr)
            } else {
                ops.append(op)
            }
            ops.append(last)
            return
        }

        switch (last, op) {
        case (.insert(let a, let aAttr), .insert(let b, let bAttr)) where aAttr == bAttr:
            ops[ops.count - 1] = .insert(a + b, aAttr)
        case (.retain(let a, let aAttr), .retain(let b, let bAttr)) where aAttr == bAttr:
            ops[ops.count - 1] = .retain(a + b, aAttr)
        case (.delete(let a), .delete(let b)):
            ops[ops.count - 1] = .delete(a + b)
        default:
            ops.append(op)
            last = op
        }
    }

    @discardableResult
    public mutating func insert(_ text: String, _ attributes: Attributes? = nil) -> Delta {
        push(.insert(text, attributes)); return self
    }

    @discardableResult
    public mutating func retain(_ length: Int, _ attributes: Attributes? = nil) -> Delta {
        push(.retain(length, attributes)); return self
    }

    @discardableResult
    public mutating func delete(_ length: Int) -> Delta {
        push(.delete(length)); return self
    }

    /// Drop a trailing plain `retain`, which is always implied.
    public func chop() -> Delta {
        guard case.retain(_, let attrs)? = ops.last, attrs == nil else { return self }
        var copy = self
        copy.ops.removeLast()
        return copy
    }

    public func concat(_ other: Delta) -> Delta {
        var result = self
        for op in other.ops { result.push(op) }
        return result
    }

    /// Slice of a *document* delta by UTF-16 range `[start, end)`.
    public func slice(_ start: Int, _ end: Int) -> Delta {
        var result = Delta()
        var iter = OpIterator(ops)
        var index = 0
        while index < end, iter.hasNext {
            let op: Op
            if index < start {
                op = iter.next(start - index)
            } else {
                op = iter.next(end - index)
                result.push(op)
            }
            index += op.length
        }
        return result
    }

    // MARK: - Core algebra

    /// Apply `other` on top of `self`. `a.compose(b)` is the single delta
    /// equivalent to applying `a` then `b`.
    public func compose(_ other: Delta) -> Delta {
        var thisIter = OpIterator(ops)
        var otherIter = OpIterator(other.ops)
        var result = Delta()

        while thisIter.hasNext || otherIter.hasNext {
            if otherIter.peekType.isInsert {
                result.push(otherIter.next())
                continue
            }
            if thisIter.peekType.isDelete {
                result.push(thisIter.next())
                continue
            }
            let length = min(thisIter.peekLength, otherIter.peekLength)
            let thisOp = thisIter.next(length)
            let otherOp = otherIter.next(length)

            if otherOp.isRetain {
                let merged = Attr.compose(thisOp.attributes, otherOp.attributes,
                                          keepNull: thisOp.isRetain)
                switch thisOp {
                case.insert(let t, _): result.push(.insert(t, merged))
                case.retain: result.push(.retain(length, merged))
                case.delete: result.push(thisOp)
                }
            } else if otherOp.isDelete, thisOp.isRetain {
                result.push(otherOp)
            }
            // other=delete + this=insert cancel each other: emit nothing.
        }
        return result.chop()
    }

    /// Rebase `other` so it can be applied after `self`.
    ///
    /// `priority == true` means `self` is treated as having happened first when
    /// two inserts land at the same position.
    public func transform(_ other: Delta, priority: Bool) -> Delta {
        var thisIter = OpIterator(ops)
        var otherIter = OpIterator(other.ops)
        var result = Delta()

        while thisIter.hasNext || otherIter.hasNext {
            if thisIter.peekType.isInsert, priority || !otherIter.peekType.isInsert {
                result.retain(thisIter.next().length)
                continue
            }
            if otherIter.peekType.isInsert {
                result.push(otherIter.next())
                continue
            }
            let length = min(thisIter.peekLength, otherIter.peekLength)
            let thisOp = thisIter.next(length)
            let otherOp = otherIter.next(length)

            if thisOp.isDelete {
                continue                       // our delete subsumes theirs
            } else if otherOp.isDelete {
                result.push(otherOp)
            } else {
                result.retain(length, Attr.transform(thisOp.attributes,
                                                     otherOp.attributes,
                                                     priority: priority))
            }
        }
        return result.chop()
    }

    /// Rebase a text position through this delta.
    ///
    /// Counterpart of Quill's `transformTextPosition`. This
    /// is what keeps a suggestion anchored to the right words when the user has
    /// typed since the suggestion was produced.
    public func transformPosition(_ position: Int, priority: Bool = false) -> Int {
        var iter = OpIterator(ops)
        var offset = 0
        var index = position

        while iter.hasNext, offset <= index {
            let length = iter.peekLength
            let type = iter.peekType
            _ = iter.next()

            if type.isDelete {
                index -= min(length, index - offset)
                continue
            } else if type.isInsert, offset < index || !priority {
                index += length
            }
            offset += length
        }
        return index
    }

    /// Rebase a caret position. Unlike `transformPosition`, an insert sitting
    /// exactly at the caret pushes the caret right.
    ///
    /// Counterpart of Quill's `transformCursorPosition`.
    public func transformCursorPosition(_ position: Int) -> Int {
        transformPosition(position, priority: false)
    }

    /// The delta that undoes `self`, given the document it was applied to.
    public func invert(against base: Delta) -> Delta {
        var inverted = Delta()
        var baseIndex = 0

        for op in ops {
            switch op {
            case.insert(let text, _):
                inverted.delete(text.utf16Length)

            case.retain(let n, let attrs):
                if attrs == nil || attrs!.isEmpty {
                    inverted.retain(n)
                } else {
                    let slice = base.slice(baseIndex, baseIndex + n)
                    for baseOp in slice.ops {
                        inverted.retain(baseOp.length,
                                        Attr.invert(attrs, base: baseOp.attributes))
                    }
                }
                baseIndex += n

            case.delete(let n):
                let slice = base.slice(baseIndex, baseIndex + n)
                for baseOp in slice.ops { inverted.push(baseOp) }
                baseIndex += n
            }
        }
        return inverted.chop()
    }

    /// Iterate the document a line at a time.
    public func eachLine(separator: Character = "\n", _ body: (Delta, Int) -> Void) {
        var line = Delta()
        var index = 0
        for op in ops {
            guard case.insert(let text, let attrs) = op else { continue }
            var remainder = text
            while let range = remainder.firstIndex(of: separator) {
                let head = String(remainder[remainder.startIndex..<range])
                if !head.isEmpty { line.insert(head, attrs) }
                body(line, index)
                index += 1
                line = Delta()
                remainder = String(remainder[remainder.index(after: range)...])
            }
            if !remainder.isEmpty { line.insert(remainder, attrs) }
        }
        if !line.isEmpty { body(line, index) }
    }
}

extension Delta: CustomStringConvertible {
    public var description: String {
        "Delta(" + ops.map { op in
            switch op {
            case.insert(let t, _): return "insert(\(t.debugDescription))"
            case.retain(let n, _): return "retain(\(n))"
            case.delete(let n): return "delete(\(n))"
            }
        }.joined(separator: ", ") + ")"
    }
}
