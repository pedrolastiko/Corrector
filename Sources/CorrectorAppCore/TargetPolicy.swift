import Foundation

/// What the global shortcut found under the cursor when it fired.
///
/// Deliberately a plain value rather than an `AXUIElement`: deciding whether
/// to act on a field and *reading* that field from the Accessibility API are
/// different jobs, and only the first one is worth testing. The app layer
/// fills this in; everything below is pure.
public struct FocusedFieldInfo: Equatable, Sendable {
    public var bundleIdentifier: String?
    /// `kAXRoleAttribute`, e.g. `AXTextField`, `AXTextArea`.
    public var role: String?
    /// `kAXSubroleAttribute`, e.g. `AXSecureTextField`.
    public var subrole: String?

    public init(bundleIdentifier: String? = nil,
                role: String? = nil,
                subrole: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.subrole = subrole
    }
}

/// Whether the shortcut may touch what it found.
public enum TargetDecision: Equatable, Sendable {
    case allowed
    /// A password field. Copying out of one is the single worst thing this
    /// tool could do.
    case refusedSecureField
    /// An application the user (or the shipped defaults) excluded.
    case refusedApplication(String)
}

/// Where the global shortcut is allowed to act.
///
/// A replacement mechanism that can fall back to copy and paste is not safe
/// everywhere: a password field must never be read at all, and a shell prompt
/// treats a pasted newline as a command. The honest response is to name those
/// places and refuse in them, rather than hope.
public enum TargetPolicy {

    /// Roles and subroles macOS uses for password entry.
    ///
    /// Checked against both attributes because the two differ by framework:
    /// AppKit reports `AXSecureTextField` as the *role*, while web content
    /// and several toolkits report a generic text role with the secure
    /// subrole underneath.
    public static let secureIdentifiers: Set<String> = [
        "AXSecureTextField",
        "AXSecureTextArea",
    ]

    /// Applications excluded out of the box.
    ///
    /// Two different hazards, both real:
    ///
    /// - Password managers. The whole point of the clipboard path is that it
    ///   copies whatever is selected; in a vault that is a credential.
    /// - Terminals. ⌘V at a shell prompt does not *replace* a selection, it
    ///   inserts at the cursor — so correcting a selected command would
    ///   append text to a command line instead of fixing it, and a newline in
    ///   the corrected text would run it. Nothing about a shell command
    ///   wants spell-checking anyway.
    public static let defaultBlockedApplications: Set<String> = [
        // Password managers
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.lastpass.LastPass",
        "com.bitwarden.desktop",
        // Terminals
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
    ]

    /// The decision, from the field alone. No side effects, no I/O.
    public static func decide(for field: FocusedFieldInfo,
                              blockedApplications: Set<String>
                                = defaultBlockedApplications) -> TargetDecision {
        if isSecure(field) { return .refusedSecureField }
        if let bundle = field.bundleIdentifier, blockedApplications.contains(bundle) {
            return .refusedApplication(bundle)
        }
        return .allowed
    }

    /// Whether this field is a password field.
    ///
    /// Unknown roles are *not* treated as secure. An Electron application that
    /// exposes nothing through Accessibility reports no role at all, and
    /// refusing everywhere the API is silent would disable the feature in most
    /// of the applications it exists to serve. The secure-field check is a
    /// guard against a specific, recognisable hazard, not a whitelist.
    public static func isSecure(_ field: FocusedFieldInfo) -> Bool {
        if let role = field.role, secureIdentifiers.contains(role) { return true }
        if let subrole = field.subrole, secureIdentifiers.contains(subrole) { return true }
        return false
    }
}
