import Foundation
import CorrectorCore
import CorrectorDelta

/// The result of one checking pass.
public struct CheckResult: Sendable {
    public let alerts: [Alert]
    public let scores: Scores
    public let stats: TextStats
    public let revision: Int
    /// The language actually used, after `auto` detection resolved.
    public let language: Language
    public let dialect: Dialect
}

/// Runs the registered plugins over a document and assembles the alert set.
///
/// A registry rather than a hard-coded sequence: each rule is enabled, ordered
/// and tested on its own, and adding one means registering a plugin instead of
/// editing the engine.
public final class CheckEngine {
    public private(set) var plugins: [CheckPlugin]
    public var features: FeatureSet

    public init(plugins: [CheckPlugin] = CheckEngine.defaultPlugins,
                features: FeatureSet = .all) {
        self.plugins = plugins
        self.features = features
    }

    /// Every plugin, both languages. The engine filters by the context's
    /// language at check time, so registering all of them is correct — a
    /// French document simply never reaches the English rules.
    public static var defaultPlugins: [CheckPlugin] {
        englishPlugins + frenchPlugins
    }

    public static var englishPlugins: [CheckPlugin] { englishPlugins() }
    public static var frenchPlugins: [CheckPlugin] { frenchPlugins() }

    public static func englishPlugins(
        dictionary: SpellDictionary = TableSpellDictionary.standard
    ) -> [CheckPlugin] {
        [SpellingPlugin(dictionary: dictionary), GrammarPlugin(), PunctuationPlugin(),
         ClarityPlugin(), EngagementPlugin(), StyleGuidePlugin(), InclusivityPlugin()]
    }

    public static func frenchPlugins(
        dictionary: SpellDictionary = TableSpellDictionary.standard
    ) -> [CheckPlugin] {
        [FrenchSpellingPlugin(dictionary: dictionary), FrenchGrammarPlugin(),
         FrenchTypographyPlugin(), FrenchMarksPlugin(),
         FrenchClarityPlugin(), FrenchEngagementPlugin(), FrenchInclusivityPlugin()]
    }

    /// Plugins backed by the curated table *and* the dictionaries macOS ships.
    ///
    /// This is what the applications use. The library's own default stays the
    /// table alone, so that tests assert on a fixed vocabulary rather than on
    /// whatever Apple shipped in the current macOS release.
    public static func systemPlugins() -> [CheckPlugin] {
        let dictionary = CompositeSpellDictionary(primary: TableSpellDictionary.standard,
                                                  fallback: SystemSpellDictionary())
        return englishPlugins(dictionary: dictionary) + frenchPlugins(dictionary: dictionary)
    }

    /// An engine using the system dictionaries. Must be built and used on the
    /// main thread, because `NSSpellChecker` is not thread-safe.
    public static func system(features: FeatureSet = .all) -> CheckEngine {
        CheckEngine(plugins: systemPlugins(), features: features)
    }

    public func register(_ plugin: CheckPlugin) { plugins.append(plugin) }

    public func check(text: String, revision: Int = 0,
                      dialect: Dialect = .american) -> CheckResult {
        let context = CheckContext(text: text, revision: revision, dialect: dialect)

        var drafts: [AlertDraft] = []
        for plugin in plugins
        where features.contains(plugin.feature)
           && plugin.languages.contains(context.language) {
            drafts.append(contentsOf: plugin.check(context))
        }

        let alerts = assemble(drafts, context: context)
        let stats = TextStats.compute(for: text, language: context.language)
        let scores = Scores.compute(alerts: alerts, wordCount: stats.words)
        return CheckResult(alerts: alerts, scores: scores, stats: stats,
                           revision: revision,
                           language: context.language, dialect: context.dialect)
    }

    /// Give each draft a stable id, drop overlaps, and sort by card priority.
    private func assemble(_ drafts: [AlertDraft], context: CheckContext) -> [Alert] {
        // Stable ids: the same issue on the same span keeps its identity across
        // passes, which is what lets `AlertStore` update a card in place rather
        // than destroying and recreating it.
        var alerts = drafts.map { draft -> Alert in
            Alert(
                id: Self.stableID(pname: draft.pname, begin: draft.begin, end: draft.end),
                rev: context.revision,
                begin: draft.begin, end: draft.end,
                highlightBegin: draft.highlightBegin, highlightEnd: draft.highlightEnd,
                highlightText: context.text.utf16Slice(draft.highlightBegin ?? draft.begin,
                                                       draft.highlightEnd ?? draft.end),
                title: draft.title, details: draft.details,
                explanation: draft.explanation, examples: draft.examples,
                pname: draft.pname,
                cardLayout: CardLayout(outcome: draft.outcome, group: draft.group,
                                       userMuteCategory: draft.outcome.rawValue),
                replacements: draft.replacements,
                hasMoreInfo: !draft.explanation.isEmpty,
                canBeAddedToDictionary: draft.canBeAddedToDictionary)
        }

        alerts.sort { $0.isPriorityHigherThan($1) }

        // Two suggestions on overlapping spans would draw overlapping
        // underlines, so the higher-priority one wins.
        var kept: [Alert] = []
        for alert in alerts {
            let clashes = kept.contains { existing in
                alert.begin < existing.end && existing.begin < alert.end
            }
            if !clashes { kept.append(alert) }
        }
        return kept
    }

    /// Deterministic, collision-resistant-enough id from rule + span.
    static func stableID(pname: AlertPname, begin: Int, end: Int) -> Int {
        var hash = 1469598103934665603 as UInt64          // FNV-1a 64 offset basis
        func mix(_ value: Int) {
            var v = UInt64(bitPattern: Int64(value))
            for _ in 0..<8 {
                hash ^= v & 0xFF
                hash = hash &* 1099511628211
                v >>= 8
            }
        }
        for byte in pname.rawValue.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        mix(begin); mix(end)
        return Int(hash & 0x7FFF_FFFF)                     // positive, fits Int32
    }
}
