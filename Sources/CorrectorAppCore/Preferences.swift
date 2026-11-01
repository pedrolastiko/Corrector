import Foundation
import CorrectorCore
import CorrectorEngine

/// Settings that survive a relaunch.
///
/// SwiftUI persists a window's frame on its own, but nothing else — so without
/// this, choosing "Français" in the toolbar lasted exactly as long as the
/// process did. These are plain `UserDefaults` reads and writes rather than
/// `@AppStorage`, because `DocumentModel` is an `ObservableObject` rather than
/// a `View` and cannot use the property wrapper.
public enum Preferences {
    private enum Key {
        static let uiLocale = "ui.locale"
        static let dialect = "document.dialect"
        static let features = "checks.enabled"
        static let dictionary = "dictionary.words"
        static let mutedRules = "rules.muted"
        static let blockedApplications = "quick.blockedApplications"
    }

    /// The store these read and write.
    ///
    /// Settable so a test can point at a scratch suite instead of the real
    /// one. Nothing else should touch it: an app that swaps its own
    /// preference store at runtime has a bug, not a feature.
    static var defaults: UserDefaults = .standard

    /// Interface language. Falls back to the system's preferred language on a
    /// first launch, then to whatever the user last chose.
    public static var uiLocale: UILocale {
        get {
            guard let raw = defaults.string(forKey: Key.uiLocale),
                  let locale = UILocale(rawValue: raw) else { return .system }
            return locale
        }
        set { defaults.set(newValue.rawValue, forKey: Key.uiLocale) }
    }

    /// Document dialect. `auto` by default, which detects per document.
    public static var dialect: Dialect {
        get {
            guard let raw = defaults.string(forKey: Key.dialect),
                  let dialect = Dialect(rawValue: raw) else { return .auto }
            return dialect
        }
        set { defaults.set(newValue.rawValue, forKey: Key.dialect) }
    }

    /// Enabled checks. Stored as the option set's raw bitmask.
    public static var features: FeatureSet {
        get {
            guard defaults.object(forKey: Key.features) != nil else { return .all }
            return FeatureSet(rawValue: defaults.integer(forKey: Key.features))
        }
        set { defaults.set(newValue.rawValue, forKey: Key.features) }
    }

    /// Words the user added to their personal dictionary.
    public static var dictionary: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.dictionary) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.dictionary) }
    }

    /// Rules the user chose to stop hearing about.
    public static var mutedRules: Set<AlertPname> {
        get {
            Set((defaults.stringArray(forKey: Key.mutedRules) ?? [])
                .compactMap(AlertPname.init(rawValue:)))
        }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: Key.mutedRules) }
    }

    /// Bundle identifiers the global shortcut refuses to act in.
    ///
    /// Seeded with `TargetPolicy.defaultBlockedApplications` on first read so
    /// the dangerous cases are off by default rather than opt-in, and stored
    /// afterwards so a user who deliberately removes one keeps that choice.
    public static var blockedApplications: Set<String> {
        get {
            guard let stored = defaults.stringArray(forKey: Key.blockedApplications)
            else { return TargetPolicy.defaultBlockedApplications }
            return Set(stored)
        }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.blockedApplications) }
    }
}
