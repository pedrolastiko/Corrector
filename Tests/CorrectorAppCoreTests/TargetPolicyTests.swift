import XCTest
@testable import CorrectorAppCore

/// The guard between the global shortcut and the places it must not go.
final class TargetPolicyTests: XCTestCase {

    func testSecureFieldIsRefusedByRole() {
        // AppKit reports the secure field as the role.
        let field = FocusedFieldInfo(bundleIdentifier: "com.apple.Safari",
                                     role: "AXSecureTextField")
        XCTAssertEqual(TargetPolicy.decide(for: field), .refusedSecureField)
    }

    func testSecureFieldIsRefusedBySubrole() {
        // Web content and several toolkits report a generic role with the
        // secure subrole underneath, which is why both are checked.
        let field = FocusedFieldInfo(bundleIdentifier: "com.google.Chrome",
                                     role: "AXTextField",
                                     subrole: "AXSecureTextField")
        XCTAssertEqual(TargetPolicy.decide(for: field), .refusedSecureField)
    }

    func testSecureFieldIsRefusedEvenInAnAllowedApplication() {
        // The password check must not be reachable only through the denylist:
        // a password field in an ordinary application is still a password
        // field.
        let field = FocusedFieldInfo(bundleIdentifier: "com.apple.TextEdit",
                                     role: "AXSecureTextField")
        XCTAssertEqual(TargetPolicy.decide(for: field, blockedApplications: []),
                       .refusedSecureField)
    }

    func testOrdinaryTextFieldIsAllowed() {
        let field = FocusedFieldInfo(bundleIdentifier: "com.apple.TextEdit",
                                     role: "AXTextArea")
        XCTAssertEqual(TargetPolicy.decide(for: field), .allowed)
    }

    func testUnknownFieldIsAllowed() {
        // An Electron application that exposes nothing reports no role at all.
        // Refusing everywhere the API is silent would disable the feature in
        // most of the applications it exists to serve.
        let field = FocusedFieldInfo(bundleIdentifier: "com.microsoft.teams2")
        XCTAssertEqual(TargetPolicy.decide(for: field), .allowed)
    }

    func testBlockedApplicationIsRefusedAndNamed() {
        let field = FocusedFieldInfo(bundleIdentifier: "com.apple.Terminal",
                                     role: "AXTextArea")
        XCTAssertEqual(TargetPolicy.decide(for: field),
                       .refusedApplication("com.apple.Terminal"))
    }

    func testTerminalsAreBlockedOutOfTheBox() {
        // ⌘V at a shell prompt inserts at the cursor rather than replacing the
        // selection, so "correcting" a selected command appends to the command
        // line — and a newline in the result runs it.
        for terminal in ["com.apple.Terminal", "com.googlecode.iterm2"] {
            XCTAssertTrue(TargetPolicy.defaultBlockedApplications.contains(terminal),
                          "\(terminal) must be blocked by default")
        }
    }

    func testPasswordManagersAreBlockedOutOfTheBox() {
        for vault in ["com.apple.keychainaccess", "com.1password.1password"] {
            XCTAssertTrue(TargetPolicy.defaultBlockedApplications.contains(vault),
                          "\(vault) must be blocked by default")
        }
    }

    func testAnEmptyDenylistStillGuardsPasswordFields() {
        XCTAssertTrue(TargetPolicy.isSecure(
            FocusedFieldInfo(role: "AXSecureTextField")))
        XCTAssertFalse(TargetPolicy.isSecure(
            FocusedFieldInfo(role: "AXTextArea", subrole: "AXSearchField")))
    }
}
