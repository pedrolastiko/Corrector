import Foundation

/// What the system reports about opening Corrector at login.
///
/// Four states rather than a `Bool`, because the interesting one is the third.
/// macOS lets the user revoke a login item in System Settings without telling
/// the application, and registering while revoked *succeeds* — the app simply
/// never launches. A boolean would show that as "on" and be wrong in exactly
/// the case the user needs an explanation.
public enum LoginItemState: String, Equatable, Sendable, CaseIterable {
    /// Registered and will open at login.
    case on
    /// Not registered.
    case off
    /// Registered, but the user has to allow it in System Settings before it
    /// does anything.
    case needsApproval
    /// The system gave an answer this build does not understand. Reachable
    /// only through `@unknown default`, so that a future macOS status cannot
    /// be silently read as "off".
    case unavailable
}

/// The side that talks to the system. A protocol so the decisions below can be
/// tested without registering a real login item on whoever runs the suite.
public protocol LoginItemControlling: AnyObject {
    var state: LoginItemState { get }
    func setEnabled(_ enabled: Bool) throws
}

public enum LoginItem {

    /// What a click on the menu item should do.
    public enum Action: Equatable, Sendable {
        case enable
        case disable
        /// Nothing this app can do: the answer is in System Settings.
        case openSettings
        /// The menu item should not be clickable at all.
        case none
    }

    public static func action(for state: LoginItemState) -> Action {
        switch state {
        case .off:           return .enable
        case .on:            return .disable
        case .needsApproval: return .openSettings
        case .unavailable:   return .none
        }
    }

    /// Whether the menu item shows a checkmark.
    ///
    /// `needsApproval` is deliberately *not* ticked: the setting is on paper
    /// but has no effect, and a tick would claim otherwise.
    public static func isOn(_ state: LoginItemState) -> Bool {
        state == .on
    }

    public static func isEnabled(_ state: LoginItemState) -> Bool {
        state != .unavailable
    }

    /// The System Settings pane that holds login items, so the app can send
    /// the user straight to the only place the approval can be given.
    public static let settingsURL =
        URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
}
