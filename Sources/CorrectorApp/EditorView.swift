import SwiftUI
import AppKit
import CorrectorCore
import CorrectorDelta
import CorrectorAppCore

/// The document, with each suggestion's span underlined in its outcome colour.
///
/// The underlines are drawn inside this text view rather than overlaid on
/// another process's window, which is why they stay aligned when the document
/// scrolls, resizes or re-wraps.
///
/// `NSTextView` addresses text with `NSRange`, which counts **UTF-16 code
/// units** — the same unit the suggestion schema uses.
/// Alert offsets therefore drop straight into `NSRange` with no conversion,
/// which is exactly why that convention was carried through the model.
struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let alerts: [Alert]
    let selectedID: Int?
    let onSelect: (Int?) -> Void
    /// Reports the caret or selected range, so the toolbar can act on it.
    let onSelectionChange: (Selection) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: Metric.lg, height: Metric.lg)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        // The system checker is off here: left on, it draws a second set of
        // underlines, in a different colour, under the same words.
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.applyDecorations(alerts: alerts, selectedID: selectedID)

        // Give the editor keyboard focus once it is in a window. Opening the
        // app and having to click before typing is a small thing that feels
        // broken, and without focus the Edit menu's commands act on nothing.
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let clamped = min(selection.location, text.utf16.count)
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
        }
        context.coordinator.applyDecorations(alerts: alerts, selectedID: selectedID)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        weak var textView: NSTextView?

        init(_ parent: EditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        /// Clicking inside an underlined span selects that suggestion, so the
        /// text and the card list stay in agreement about what is being looked
        /// at.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            parent.onSelectionChange(Selection(begin: range.location,
                                               end: range.location + range.length))

            let caret = range.location
            let hit = parent.alerts.first {
                caret >= $0.highlightBegin && caret <= $0.highlightEnd
            }
            if hit?.id != parent.selectedID { parent.onSelect(hit?.id) }
        }

        func applyDecorations(alerts: [Alert], selectedID: Int?) {
            guard let textView, let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)

            // Editing the text storage collapses the selection to a caret.
            // Since the selection is published, that made selecting text
            // self-defeating: the selection triggered a re-render, the
            // re-render redrew the underlines, and redrawing destroyed the
            // selection. Save it here and put it back below.
            let selectionBefore = textView.selectedRange()

            storage.beginEditing()
            storage.removeAttribute(.underlineStyle, range: full)
            storage.removeAttribute(.underlineColor, range: full)
            storage.removeAttribute(.backgroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
            storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: full)

            for alert in alerts {
                let begin = max(0, min(alert.highlightBegin, storage.length))
                let end = max(begin, min(alert.highlightEnd, storage.length))
                guard end > begin else { continue }
                let range = NSRange(location: begin, length: end - begin)
                let isSelected = alert.id == selectedID

                storage.addAttribute(.underlineStyle,
                                     value: (isSelected
                                             ? NSUnderlineStyle.thick : NSUnderlineStyle.single).rawValue,
                                     range: range)
                storage.addAttribute(.underlineColor,
                                     value: alert.cardLayout.outcome
                                         .underlineNS(active: isSelected),
                                     range: range)
                if isSelected {
                    storage.addAttribute(.backgroundColor,
                                         value: alert.cardLayout.outcome.tintNS
                                             .withAlphaComponent(0.14),
                                         range: range)
                }
            }
            storage.endEditing()

            if textView.selectedRange() != selectionBefore,
               NSMaxRange(selectionBefore) <= storage.length {
                textView.setSelectedRange(selectionBefore)
            }
        }

        /// Scroll a suggestion into view and put the caret on it.
        func reveal(_ alert: Alert) {
            guard let textView else { return }
            let begin = max(0, min(alert.highlightBegin, textView.string.utf16.count))
            let end = max(begin, min(alert.highlightEnd, textView.string.utf16.count))
            let range = NSRange(location: begin, length: end - begin)
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
        }
    }
}
