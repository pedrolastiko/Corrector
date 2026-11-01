import Foundation

/// The decisions behind the settings screen, kept out of the views so they can
/// be tested.
///
/// Three of Corrector's preferences — the personal dictionary, the muted rules
/// and the applications the shortcut refuses to act in — were written by the
/// app and readable only through `defaults`. Adding a screen means adding the
/// operations that screen performs, and those have rules worth pinning: a word
/// added twice in different case is one word, and a bundle identifier typed by
/// hand is usually wrong.
public enum SettingsEditing {

    // MARK: - Word lists

    /// Add a word to a set, or return it unchanged.
    ///
    /// Trims, refuses blanks, and treats a differently-cased duplicate as the
    /// same word — otherwise "Kubernetes" and "kubernetes" both sit in the
    /// list and the user has to delete the one they cannot see the difference
    /// from.
    public static func adding(_ word: String, to words: Set<String>) -> Set<String> {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return words }
        guard !words.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        else { return words }
        return words.union([trimmed])
    }

    /// Remove by exact value, since that is what the list showed.
    public static func removing(_ word: String, from words: Set<String>) -> Set<String> {
        words.subtracting([word])
    }

    /// Alphabetical and case-insensitive, so a list someone scans reads the way
    /// they expect rather than putting every capital first.
    public static func sorted(_ words: Set<String>) -> [String] {
        words.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Bundle identifiers

    /// Whether a string looks like a bundle identifier.
    ///
    /// Deliberately shallow: it catches the mistakes people actually make —
    /// typing an application's name, or its path — and lets everything else
    /// through. A stricter rule would reject identifiers that are unusual but
    /// real, and the cost of a wrong entry here is only that the shortcut
    /// keeps working in an application the user wanted it to skip.
    public static func isPlausibleBundleIdentifier(_ identifier: String) -> Bool {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.contains(".") else { return false }
        guard !trimmed.hasPrefix("."), !trimmed.hasSuffix(".") else { return false }
        guard !trimmed.contains("..") else { return false }
        guard !trimmed.contains(" "), !trimmed.contains("/") else { return false }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Whether removing this identifier gives up a protection Corrector shipped
    /// with. The screen warns on these rather than refusing: it is the user's
    /// machine, but a password manager is not an obvious thing to unblock by
    /// accident.
    public static func isShippedProtection(_ identifier: String) -> Bool {
        TargetPolicy.defaultBlockedApplications.contains(identifier)
    }

    /// Put the defaults back, keeping anything the user added themselves.
    public static func restoringDefaults(in blocked: Set<String>) -> Set<String> {
        blocked.union(TargetPolicy.defaultBlockedApplications)
    }
}
