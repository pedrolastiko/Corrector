import AppKit
import Foundation
import CorrectorCore
import CorrectorEngine
import CorrectorSession
import CorrectorAppCore

/// Handles the macOS Services the app declares in its `Info.plist`.
///
/// Services are the cheapest way into other applications, and the most
/// respectful: instead of watching every editable field in every application,
/// the *system* hands over the selection, once, because the user asked for it.
/// No Accessibility permission, no event tap, no pasteboard hijacking — and
/// consent is granted per invocation rather than once and forever.
///
/// The trade-off is that nothing happens until the user invokes it, so there is
/// no live underlining. For on-demand correction that is the better bargain.
final class ServiceProvider: NSObject {

    /// Replace the selection with its corrected text.
    ///
    /// Declaring `NSReturnTypes` in the plist is what makes replacement work:
    /// whatever this writes back to the pasteboard, macOS substitutes for the
    /// selection in the originating application.
    @objc func correctSelection(_ pasteboard: NSPasteboard,
                                userData: String?,
                                error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = Self.message("No text was selected.",
                                         "Aucun texte n'était sélectionné.")
            return
        }

        // Correct, do not restyle. Applying everything blind turned
        // "c'est tres bien" into "c'est bien": the spelling fix landed, then
        // the engagement rule deleted the now-correct intensifier. Someone
        // right-clicking to fix typos has not asked for their voice to be
        // edited, so this Service sticks to objective fixes — spelling,
        // grammar, punctuation and typography. Style and engagement
        // suggestions belong in the window, where they can be reviewed one by
        // one, which is exactly what the other Service is for.
        //
        // This Service gets `reviewed` rather than the shortcut's `mechanical`
        // set: the user is looking at the selection they right-clicked, in a
        // document they have open, so a wrong grammar fix is visible
        // immediately. The global shortcut has no such guarantee.
        let outcome = SelectionCorrector(features: Self.correctionFeatures,
                                         dialect: .auto).correct(text, origin: "service")
        guard outcome.changed else {
            error.pointee = Self.message("Nothing to correct.", "Rien à corriger.")
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(outcome.text, forType: .string)
    }

    /// Send the selection to the app's window for review.
    @objc func openInCorrector(_ pasteboard: NSPasteboard,
                               userData: String?,
                               error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = Self.message("No text was selected.",
                                         "Aucun texte n'était sélectionné.")
            return
        }
        DispatchQueue.main.async {
            DocumentModel.shared.replaceDocument(with: text)
            AppDelegate.showMainWindow()
        }
    }

    /// What "Corriger la sélection" is allowed to change.
    static let correctionFeatures: FeatureSet = SelectionCorrector.reviewed

    /// Service errors surface in a system alert, which has no access to the
    /// in-app language picker, so follow the system's language instead.
    private static func message(_ english: String, _ french: String) -> NSString {
        (UILocale.system == .french ? french : english) as NSString
    }
}
