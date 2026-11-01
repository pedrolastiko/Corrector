import XCTest
import CorrectorCore
import CorrectorEngine
@testable import CorrectorAppCore

/// Settings that survive a relaunch — and, until this target existed, could
/// only be checked by quitting the app and opening it again.
final class PreferencesTests: XCTestCase {
    private var suite: UserDefaults!
    private var realDefaults: UserDefaults!
    private let suiteName = "corrector.tests.preferences"

    override func setUp() {
        super.setUp()
        realDefaults = Preferences.defaults
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        suite = UserDefaults(suiteName: suiteName)
        Preferences.defaults = suite
    }

    override func tearDown() {
        Preferences.defaults = realDefaults
        suite.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsAreSaneOnAFirstLaunch() {
        XCTAssertEqual(Preferences.dialect, .auto)
        XCTAssertEqual(Preferences.features, .all)
        XCTAssertTrue(Preferences.dictionary.isEmpty)
        XCTAssertTrue(Preferences.mutedRules.isEmpty)
    }

    func testEverySettingSurvivesAWrite() {
        Preferences.uiLocale = .french
        Preferences.dialect = .british
        Preferences.features = [.spelling, .punctuation]
        Preferences.dictionary = ["Kubernetes", "idempotent"]
        Preferences.mutedRules = [.repeatedWord]

        XCTAssertEqual(Preferences.uiLocale, .french)
        XCTAssertEqual(Preferences.dialect, .british)
        XCTAssertEqual(Preferences.features, [.spelling, .punctuation])
        XCTAssertEqual(Preferences.dictionary, ["Kubernetes", "idempotent"])
        XCTAssertEqual(Preferences.mutedRules, [.repeatedWord])
    }

    func testAnEmptyFeatureSetIsNotMistakenForUnset() {
        // `.all` is the default, so storing "nothing enabled" must not read
        // back as "everything enabled" — the distinction is whether the key
        // exists, not whether the value is zero.
        Preferences.features = []
        XCTAssertEqual(Preferences.features, [])
    }

    func testAnUnknownStoredValueFallsBackRatherThanCrashing() {
        // A preferences file written by a later version, or edited by hand.
        suite.set("klingon", forKey: "document.dialect")
        suite.set("not-a-locale", forKey: "ui.locale")
        XCTAssertEqual(Preferences.dialect, .auto)
        XCTAssertEqual(Preferences.uiLocale, .system)
    }

    // MARK: - The denylist

    func testTheDenylistIsSeededWithTheDangerousApplications() {
        XCTAssertEqual(Preferences.blockedApplications,
                       TargetPolicy.defaultBlockedApplications)
    }

    func testRemovingAnApplicationFromTheDenylistSticks() {
        // Opting back in must not be undone by the defaults being re-seeded
        // on the next read.
        var blocked = Preferences.blockedApplications
        blocked.remove("com.apple.Terminal")
        Preferences.blockedApplications = blocked

        XCTAssertFalse(Preferences.blockedApplications.contains("com.apple.Terminal"))
        XCTAssertTrue(Preferences.blockedApplications.contains("com.apple.keychainaccess"))
    }

    func testAnEmptyDenylistIsRespected() {
        Preferences.blockedApplications = []
        XCTAssertTrue(Preferences.blockedApplications.isEmpty,
                      "an empty list must not read back as the defaults")
    }
}
