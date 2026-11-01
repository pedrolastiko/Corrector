import AppKit
import ApplicationServices
import CorrectorAppCore

/// The text field the user is actually typing in, wherever that is.
///
/// Two jobs, both needing the same Accessibility handle: deciding whether
/// Corrector may touch this field at all, and — when the application
/// cooperates — reading and replacing the selection directly, without going
/// anywhere near the clipboard.
///
/// Every call here returns an optional and means it. The Accessibility API is
/// available in AppKit applications, partially available in Electron ones
/// (only once they have switched their own accessibility support on), and
/// absent in anything drawing its own text. That is precisely why the
/// clipboard path stays: this is the better road when it exists, not a
/// replacement for the one that always exists.
enum FocusedField {

    /// The focused element and what we can say about it.
    ///
    /// Returns `nil` for the element when nothing is focused or the
    /// application exposes nothing; `info` still carries the bundle
    /// identifier, because a per-application rule has to apply even when the
    /// field itself is invisible to us.
    static func current() -> (element: AXUIElement?, info: FocusedFieldInfo) {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return (nil, FocusedFieldInfo())
        }
        var info = FocusedFieldInfo(bundleIdentifier: app.bundleIdentifier)

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = copyElement(appElement, kAXFocusedUIElementAttribute) else {
            return (nil, info)
        }
        info.role = copyString(focused, kAXRoleAttribute)
        info.subrole = copyString(focused, kAXSubroleAttribute)
        return (focused, info)
    }

    /// The selected text, if the element will tell us.
    ///
    /// An empty string means "focused, nothing selected", which is a different
    /// answer from `nil` ("this element does not answer the question") — and
    /// the caller treats them differently: the first is a dead end, the second
    /// means fall back to the clipboard.
    static func selectedText(of element: AXUIElement) -> String? {
        copyString(element, kAXSelectedTextAttribute)
    }

    /// Replace the selection in place.
    ///
    /// `kAXSelectedTextAttribute` is writable on cooperating elements, and
    /// setting it substitutes the text the same way typing would: the
    /// application's own undo stack records it, surrounding formatting
    /// survives, and the user's clipboard is never touched.
    ///
    /// Returns whether the write was accepted. A `false` here is normal, not
    /// exceptional — plenty of elements expose the attribute read-only.
    static func replaceSelectedText(of element: AXUIElement, with text: String) -> Bool {
        // Ask before writing. Several applications return `.success` from a
        // set on a read-only attribute and quietly discard it, which would
        // leave us reporting a correction that never happened.
        var settable = DarwinBoolean(false)
        let canSet = AXUIElementIsAttributeSettable(
            element, kAXSelectedTextAttribute as CFString, &settable)
        guard canSet == .success, settable.boolValue else { return false }

        let result = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        return result == .success
    }

    // MARK: - Attribute plumbing

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }
}
