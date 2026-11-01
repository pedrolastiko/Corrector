import XCTest
@testable import CorrectorAppCore

/// Opening at login. The logic is small; the reason it is split out at all is
/// the `needsApproval` state, which is the one a boolean would get wrong.
final class LoginItemTests: XCTestCase {

    func testEachStateLeadsToTheRightAction() {
        XCTAssertEqual(LoginItem.action(for: .off), .enable)
        XCTAssertEqual(LoginItem.action(for: .on), .disable)
        XCTAssertEqual(LoginItem.action(for: .needsApproval), .openSettings)
        XCTAssertEqual(LoginItem.action(for: .unavailable), .none)
    }

    func testApprovalPendingIsNotShownAsOn() {
        // macOS reports `requiresApproval` for a login item it has registered
        // but the user has not allowed. Registering succeeds and the app still
        // never launches, so a tick here would be a claim the system does not
        // back. This is the whole reason the state is not a Bool.
        XCTAssertFalse(LoginItem.isOn(.needsApproval))
        XCTAssertTrue(LoginItem.isOn(.on))
        XCTAssertFalse(LoginItem.isOn(.off))
        XCTAssertFalse(LoginItem.isOn(.unavailable))
    }

    func testOnlyAnUnanswerableStateDisablesTheMenuItem() {
        for state in LoginItemState.allCases {
            XCTAssertEqual(LoginItem.isEnabled(state), state != .unavailable,
                           "\(state)")
        }
    }

    func testNoStateIsLeftWithoutAnAction() {
        // A new case added to the enum must be given an action here, not fall
        // through to whatever `.none` happens to mean.
        for state in LoginItemState.allCases {
            let action = LoginItem.action(for: state)
            if state == .unavailable {
                XCTAssertEqual(action, .none)
            } else {
                XCTAssertNotEqual(action, .none, "\(state) has no action")
            }
        }
    }

    func testTheSettingsLinkPointsAtTheLoginItemsPane() {
        let url = LoginItem.settingsURL.absoluteString
        XCTAssertTrue(url.hasPrefix("x-apple.systempreferences:"), url)
        XCTAssertTrue(url.contains("LoginItems"), url)
    }

    // MARK: - Through a fake system

    private final class FakeService: LoginItemControlling {
        var state: LoginItemState
        var lastSet: Bool?
        var shouldThrow = false
        init(_ state: LoginItemState) { self.state = state }
        func setEnabled(_ enabled: Bool) throws {
            if shouldThrow { throw CocoaError(.fileWriteNoPermission) }
            lastSet = enabled
            state = enabled ? .on : .off
        }
    }

    func testTurningItOnAndOffRoundTrips() throws {
        let service = FakeService(.off)
        try service.setEnabled(true)
        XCTAssertEqual(service.state, .on)
        XCTAssertEqual(LoginItem.action(for: service.state), .disable)
        try service.setEnabled(false)
        XCTAssertEqual(service.state, .off)
        XCTAssertEqual(LoginItem.action(for: service.state), .enable)
    }

    func testAFailureLeavesTheStateUntouched() {
        let service = FakeService(.off)
        service.shouldThrow = true
        XCTAssertThrowsError(try service.setEnabled(true))
        XCTAssertEqual(service.state, .off,
                       "a refused registration must not look like it worked")
        XCTAssertNil(service.lastSet)
    }
}
