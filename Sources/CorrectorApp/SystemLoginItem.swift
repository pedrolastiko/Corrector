import AppKit
import Combine
import ServiceManagement
import CorrectorAppCore

/// The real login item, through `SMAppService`.
///
/// `SMAppService.mainApp` registers *this* bundle, which is why there is no
/// separate helper application to build and sign — the approach the older
/// `SMLoginItemSetEnabled` required. The registration follows the bundle, so
/// moving Corrector after enabling this means registering it again from its
/// new home.
final class SystemLoginItem: LoginItemControlling {

    var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled:          return .on
        case .notRegistered:    return .off
        case .requiresApproval: return .needsApproval
        // `.notFound` reads like a dead end and is not one. It is what the
        // system answers for a bundle Background Task Management has never
        // seen — which is every app before its first registration. Measured,
        // not assumed: from `.notFound`, `register()` succeeds and the status
        // then reports `.enabled`. Treating it as unavailable disabled the
        // menu item in exactly the case it exists for, the first run.
        case .notFound:         return .off
        @unknown default:       return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Holds the login-item state for the menu.
///
/// The system is the source of truth and nothing is cached in `Preferences`:
/// the user can turn this off in System Settings without the app running, so a
/// stored copy would start lying the moment they did. The state is re-read
/// every time the menu opens instead, which costs one call.
@MainActor
final class LoginItemModel: ObservableObject {
    @Published private(set) var state: LoginItemState = .off
    /// Set when the system refuses a change, so the menu can say so instead of
    /// appearing to do nothing.
    @Published private(set) var failure: String?

    private let service: LoginItemControlling

    init(service: LoginItemControlling = SystemLoginItem()) {
        self.service = service
        refresh()
    }

    func refresh() {
        state = service.state
    }

    /// Act on the current state. Returns nothing: the menu reads `state`
    /// afterwards, so there is one path from system to screen rather than two.
    func activate() {
        switch LoginItem.action(for: state) {
        case .enable, .disable:
            let wanted = LoginItem.action(for: state) == .enable
            do {
                try service.setEnabled(wanted)
                failure = nil
            } catch {
                // Registering can fail on a bundle macOS will not vouch for —
                // one still in a build folder, say. Saying so beats a switch
                // that flips back on its own.
                failure = error.localizedDescription
            }
        case .openSettings:
            NSWorkspace.shared.open(LoginItem.settingsURL)
        case .none:
            break
        }
        refresh()
    }
}
