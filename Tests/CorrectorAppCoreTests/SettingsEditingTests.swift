import XCTest
@testable import CorrectorAppCore

/// The settings screen's decisions. Small operations, but each one is a place
/// a list can quietly acquire an entry the user cannot get rid of.
final class SettingsEditingTests: XCTestCase {

    // MARK: - Words

    func testAddingTrimsAndRefusesBlanks() {
        XCTAssertEqual(SettingsEditing.adding("  swiftly  ", to: []), ["swiftly"])
        XCTAssertEqual(SettingsEditing.adding("   ", to: ["a"]), ["a"])
        XCTAssertEqual(SettingsEditing.adding("", to: ["a"]), ["a"])
        XCTAssertEqual(SettingsEditing.adding("\n\t", to: []), [])
    }

    func testADifferentlyCasedDuplicateIsTheSameWord() {
        // Otherwise the list holds "Kubernetes" and "kubernetes" and the user
        // has to delete one they cannot tell apart at a glance.
        let words: Set<String> = ["Kubernetes"]
        XCTAssertEqual(SettingsEditing.adding("kubernetes", to: words), words)
        XCTAssertEqual(SettingsEditing.adding("KUBERNETES", to: words), words)
        XCTAssertEqual(SettingsEditing.adding("Kubernetes", to: words), words)
    }

    func testTheFirstSpellingIsTheOneKept() {
        let words = SettingsEditing.adding("GitHub", to: [])
        XCTAssertEqual(SettingsEditing.adding("github", to: words), ["GitHub"])
    }

    func testRemovingTakesTheExactValueTheListShowed() {
        XCTAssertEqual(SettingsEditing.removing("b", from: ["a", "b"]), ["a"])
        XCTAssertEqual(SettingsEditing.removing("B", from: ["a", "b"]), ["a", "b"])
    }

    func testSortingIgnoresCase() {
        // A plain `sorted()` puts every capital first, which reads as a bug in
        // a list someone is scanning for one word.
        XCTAssertEqual(SettingsEditing.sorted(["banana", "Apple", "cherry"]),
                       ["Apple", "banana", "cherry"])
    }

    // MARK: - Bundle identifiers

    func testPlausibleIdentifiersAreAccepted() {
        for identifier in ["com.apple.Terminal", "dev.warp.Warp-Stable",
                           "com.1password.1password", "co.zeit.hyper",
                           "org.mozilla.firefox"] {
            XCTAssertTrue(SettingsEditing.isPlausibleBundleIdentifier(identifier),
                          identifier)
        }
    }

    func testTheMistakesPeopleActuallyMakeAreRejected() {
        // Typing the application's name, or dragging in its path.
        for identifier in ["Terminal", "", "   ", "a",
                           "/Applications/Terminal.app",
                           "com apple Terminal", ".com.apple", "com.apple.",
                           "com..apple"] {
            XCTAssertFalse(SettingsEditing.isPlausibleBundleIdentifier(identifier),
                           identifier)
        }
    }

    func testWhitespaceAroundAnIdentifierIsForgiven() {
        XCTAssertTrue(
            SettingsEditing.isPlausibleBundleIdentifier("  com.apple.Terminal \n"))
    }

    // MARK: - Shipped protections

    func testTheShippedBlocksAreRecognised() {
        XCTAssertTrue(SettingsEditing.isShippedProtection("com.apple.Terminal"))
        XCTAssertTrue(SettingsEditing.isShippedProtection("com.apple.keychainaccess"))
        XCTAssertFalse(SettingsEditing.isShippedProtection("com.example.notes"))
    }

    func testRestoringDefaultsKeepsWhatTheUserAdded() {
        let theirs = "com.example.notes"
        let restored = SettingsEditing.restoringDefaults(in: [theirs])
        XCTAssertTrue(restored.contains(theirs),
                      "restoring defaults must not delete the user's own entries")
        XCTAssertTrue(TargetPolicy.defaultBlockedApplications.isSubset(of: restored))
    }

    func testRestoringDefaultsBringsBackOneTheUserRemoved() {
        var blocked = TargetPolicy.defaultBlockedApplications
        blocked.remove("com.apple.Terminal")
        XCTAssertTrue(
            SettingsEditing.restoringDefaults(in: blocked).contains("com.apple.Terminal"))
    }
}
