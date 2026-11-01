import AppKit
import Carbon.HIToolbox
import CorrectorCore
import CorrectorEngine
import CorrectorSession
import CorrectorAppCore

/// Correct the selected text in whatever application is frontmost.
///
/// Two roads, tried in order.
///
/// The good one: the Accessibility API hands us the focused element, we read
/// `AXSelectedText` from it and write the corrected text straight back. The
/// application's own undo stack records the change, surrounding formatting
/// survives, and the user's clipboard is never touched. It works wherever the
/// application cooperates, which means AppKit apps and the Electron ones that
/// have switched their accessibility support on.
///
/// The universal one: synthesise ⌘C, read what lands on the clipboard,
/// correct it, put it back and synthesise ⌘V. Crude — it borrows the
/// clipboard, loses rich formatting and leaves one undo step covering the
/// whole replacement — but it works anywhere copy and paste work, which is
/// everywhere.
///
/// The clipboard stays the last resort rather than the default: it is the road
/// that cannot be refused, but every one of its costs is real. Both roads need
/// Accessibility trust, so there is no permission argument for preferring the
/// worse one.
///
/// Nothing is monitored. One keystroke, one round trip, and
/// `TargetPolicy` gets a veto before either road is taken.
@MainActor
final class QuickCorrect {
    private var hotKey: HotKey?

    /// Spelling and punctuation only — see `SelectionCorrector.mechanical`.
    /// This path replaces text the user is not watching, in a document
    /// Corrector cannot show them, so it applies only the rules that cannot
    /// be a matter of opinion.
    private let corrector = SelectionCorrector(features: SelectionCorrector.mechanical,
                                               dialect: .auto)

    /// Time to let the frontmost application answer a synthetic ⌘C or ⌘V.
    ///
    /// How long an application takes to answer varies by an order of magnitude
    /// between a native field and a Chromium view, so this is deliberately
    /// generous — and the result is verified against the pasteboard's change
    /// count afterwards rather than trusted to the clock.
    private let pasteboardSettle = Duration.milliseconds(120)

    /// ⌥⌘C. Chosen to avoid ⌘⇧C, which the app already uses for its own copy.
    func install() {
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_C),
                        modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            Task { @MainActor in await self?.correctFrontmostSelection() }
        }
        // Log the permission at launch, not only when the shortcut is pressed.
        // Registering succeeds without Accessibility trust and acting needs
        // it, so the two were only ever observable together — meaning the
        // answer to "is it set up?" required pressing the key and watching
        // nothing happen.
        log((hotKey == nil ? "hotkey registration FAILED" : "hotkey registered")
            + "; accessibility trusted = \(canSynthesiseKeys)"
            + "; bundle = \(Bundle.main.bundlePath)")
    }

    /// Whether macOS will let us post synthetic keystrokes.
    ///
    /// Registering the shortcut needs no permission, but *acting* on it does:
    /// `CGEvent.post` is silently ignored unless the app is trusted for
    /// Accessibility. Discovering that only when nothing happens is exactly
    /// the kind of silent failure worth surfacing.
    var canSynthesiseKeys: Bool { AXIsProcessTrusted() }

    /// Ask for the permission, showing the system's own prompt once.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Append a line to a log the user (and I) can read when this misbehaves.
    private func log(_ message: String) {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Corrector/quick.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let line = "\(Date().formatted(date: .omitted, time: .standard))  \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    var isInstalled: Bool { hotKey != nil }

    // MARK: - The round trip

    func correctFrontmostSelection() async {
        log("triggered; accessibility trusted = \(canSynthesiseKeys)")
        guard canSynthesiseKeys else {
            // Without this permission neither road is open: the synthetic ⌘C
            // goes nowhere and the Accessibility query returns nothing.
            notify(.needsPermission)
            requestAccessibility()
            return
        }

        // Ask what we are pointed at before touching anything. This is the
        // only check standing between the shortcut and a password field.
        let (element, info) = FocusedField.current()
        log("focus: app=\(info.bundleIdentifier ?? "?") role=\(info.role ?? "?") "
            + "subrole=\(info.subrole ?? "?")")

        switch TargetPolicy.decide(for: info,
                                   blockedApplications: Preferences.blockedApplications) {
        case .refusedSecureField:
            notify(.refusedSecureField)
            return
        case .refusedApplication(let bundle):
            notify(.refusedApplication(Self.displayName(for: bundle) ?? bundle))
            return
        case .allowed:
            break
        }

        // The good road first.
        if let element, correctInPlace(element) { return }

        // The universal one.
        await correctViaPasteboard()
    }

    // MARK: - Accessibility replacement

    /// Read, correct and write the selection through the Accessibility API.
    ///
    /// Returns whether it handled the keystroke — including the cases where it
    /// handled it by finding nothing to do. Returning `false` means "this
    /// element could not answer", which is the only case that should fall
    /// through to the clipboard.
    private func correctInPlace(_ element: AXUIElement) -> Bool {
        guard let selected = FocusedField.selectedText(of: element) else {
            log("AX: element does not expose a selection")
            return false
        }
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Focused, answering, nothing selected. The clipboard road would
            // reach the same dead end one synthetic ⌘C later.
            log("AX: nothing selected")
            notify(.nothingSelected)
            return true
        }

        let outcome = corrector.correct(selected, origin: "quick")
        guard outcome.changed else {
            log("AX: already correct")
            notify(.alreadyCorrect)
            return true
        }

        guard FocusedField.replaceSelectedText(of: element, with: outcome.text) else {
            // Readable but not writable — common. Fall through rather than
            // telling the user we fixed something we did not.
            log("AX: selection is read-only, falling back to the clipboard")
            return false
        }
        log("AX: replaced in place, \(outcome.applied) applied")
        notify(.corrected(outcome.applied))
        return true
    }

    // MARK: - Clipboard round trip

    private func correctViaPasteboard() async {
        let pasteboard = NSPasteboard.general

        // Remember what the user had, so we can hand it back. Only the string
        // is preserved: restoring every representation of an arbitrary
        // pasteboard is not reliably possible, and quietly losing a copied
        // image would be worse than saying so.
        let previous = pasteboard.string(forType: .string)
        let changeCountBefore = pasteboard.changeCount

        synthesize(keyCode: UInt32(kVK_ANSI_C), command: true)
        try? await Task.sleep(for: pasteboardSettle)

        // Verify rather than assume: if the clipboard did not change, the
        // application ignored the copy and there is nothing selected to fix.
        log("clipboard changed = \(pasteboard.changeCount != changeCountBefore)")
        guard pasteboard.changeCount != changeCountBefore,
              let selected = pasteboard.string(forType: .string),
              !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            restore(previous, to: pasteboard)
            notify(.nothingSelected)
            return
        }

        let outcome = corrector.correct(selected, origin: "quick")
        guard outcome.changed else {
            restore(previous, to: pasteboard)
            notify(.alreadyCorrect)
            return
        }

        pasteboard.clearContents()
        pasteboard.setString(outcome.text, forType: .string)
        try? await Task.sleep(for: pasteboardSettle)
        synthesize(keyCode: UInt32(kVK_ANSI_V), command: true)

        // Give the paste time to consume the clipboard before handing the
        // user's own content back, or the application pastes the wrong thing.
        try? await Task.sleep(for: .milliseconds(250))
        restore(previous, to: pasteboard)
        notify(.corrected(outcome.applied))
    }

    /// The name a user would recognise, for a bundle identifier.
    private static func displayName(for bundle: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
        else { return nil }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func restore(_ text: String?, to pasteboard: NSPasteboard) {
        guard let text else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Synthetic keys

    /// Post a key down/up pair to the session.
    ///
    /// This posts two specific keystrokes on demand. It does not install a tap
    /// and cannot observe anything the user types.
    private func synthesize(keyCode: UInt32, command: Bool) {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents], state: .eventSuppressionStateSuppressionInterval)

        let down = CGEvent(keyboardEventSource: source,
                           virtualKey: CGKeyCode(keyCode), keyDown: true)
        let up = CGEvent(keyboardEventSource: source,
                         virtualKey: CGKeyCode(keyCode), keyDown: false)
        if command {
            down?.flags = .maskCommand
            up?.flags = .maskCommand
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Feedback

    enum Outcome {
        case corrected(Int)
        case alreadyCorrect
        case nothingSelected
        case needsPermission
        case refusedSecureField
        case refusedApplication(String)

        /// Only an actual correction gets the cheerful sound.
        var succeeded: Bool {
            if case .corrected = self { return true }
            return false
        }
    }

    /// The user is looking at another application, so feedback has to come
    /// from somewhere visible: a notification rather than our own window.
    private func notify(_ outcome: Outcome) {
        let strings = Strings(locale: Preferences.uiLocale)
        let message: String
        switch outcome {
        case .corrected(let count): message = strings.quickCorrected(count)
        case .alreadyCorrect: message = strings.quickAlreadyCorrect
        case .nothingSelected: message = strings.quickNothingSelected
        case .needsPermission: message = strings.quickNeedsPermission
        case .refusedSecureField: message = strings.quickRefusedSecureField
        case .refusedApplication(let name): message = strings.quickRefusedApplication(name)
        }
        log("outcome: \(message)")
        NSSound(named: outcome.succeeded ? "Pop" : "Funk")?.play()
        DocumentModel.shared.flashStatus(message)
    }
}
