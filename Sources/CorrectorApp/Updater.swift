import AppKit
import Combine
import Sparkle
import CorrectorAppCore

/// Software updates, through Sparkle.
///
/// Corrector is distributed outside the App Store, so nothing tells anyone a
/// new version exists. Without this, 0.5.1 stays 0.5.1 on every machine that
/// installed it.
///
/// Sparkle needs two things in `Info.plist` to work: `SUFeedURL`, the appcast
/// it polls, and `SUPublicEDKey`, the key every update must be signed with.
/// The second is what stops an attacker who controls the feed from shipping
/// whatever they like — which is why this refuses to run at all without it
/// rather than falling back to an unsigned check. A build made before the
/// release keys exist reports `isConfigured == false`, and the menu says so
/// instead of offering a button that does nothing.
@MainActor
final class Updater: ObservableObject {

    private let controller: SPUStandardUpdaterController?

    /// Whether this build can check at all.
    let isConfigured: Bool

    @Published var checksAutomatically: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String) ?? ""
        let key = (info["SUPublicEDKey"] as? String) ?? ""
        isConfigured = !feed.isEmpty && !key.isEmpty

        guard isConfigured else {
            controller = nil
            checksAutomatically = false
            return
        }

        // `startingUpdater: true` lets Sparkle schedule its own background
        // checks. The user-driven check below goes through the same object, so
        // there is one updater rather than two disagreeing about state.
        let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                      updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
    }

    /// Whether the menu item should be clickable right now. Sparkle refuses a
    /// second check while one is in flight, and says so through this.
    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
