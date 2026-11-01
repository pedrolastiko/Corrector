import Foundation

/// Offsets throughout Corrector are **UTF-16 code-unit offsets**.
///
/// Rationale: `NSTextView` addresses text with `NSRange` and the Accessibility
/// API answers in the same unit, so UTF-16 is what every surface Corrector
/// talks to already speaks. `Character` offsets would mean converting at every
/// boundary, and mis-placing a highlight on any text containing emoji, flags or
/// combining marks.
public extension String {
    /// Length of the string in UTF-16 code units.
    var utf16Length: Int { utf16.count }

    /// Substring by UTF-16 code-unit range, clamped to bounds.
    func utf16Slice(from start: Int, length: Int) -> String {
        let units = Array(utf16)
        let lo = max(0, min(start, units.count))
        let hi = max(lo, min(start + max(0, length), units.count))
        guard lo < hi else { return "" }
        return String(utf16CodeUnits: Array(units[lo..<hi]), count: hi - lo)
    }

    /// Substring for a half-open UTF-16 range `[start, end)`.
    func utf16Slice(_ start: Int, _ end: Int) -> String {
        utf16Slice(from: start, length: end - start)
    }
}
