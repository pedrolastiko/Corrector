import XCTest
import CorrectorCore
@testable import CorrectorEngine

final class FrenchEngineTests: XCTestCase {

    private func alerts(_ text: String,
                        features: FeatureSet = .all,
                        dialect: Dialect = .french) -> [Alert] {
        CheckEngine(features: features).check(text: text, dialect: dialect).alerts
    }

    private func pnames(_ text: String,
                        features: FeatureSet = .all,
                        dialect: Dialect = .french) -> Set<AlertPname> {
        Set(alerts(text, features: features, dialect: dialect).map(\.pname))
    }

    // MARK: - Language routing
    //
    // The point of the language dimension: the two rule sets must not mix.

    func testFrenchTextDoesNotGetEnglishRules() {
        // "très" would be a weak intensifier in the French engagement plugin,
        // but the English list must never fire on French text.
        let found = alerts("Le systeme est very good.", dialect: .french)
        XCTAssertFalse(found.contains { $0.title == "Weak intensifier" })
    }

    func testEnglishTextDoesNotGetFrenchRules() {
        // French typography demands a space before "!"; English forbids it.
        // Checking English must never produce the French spacing rule.
        XCTAssertFalse(pnames("Ship it now!", dialect: .american).contains(.frenchSpacing))
    }

    func testSpaceBeforeExclamationIsAnErrorInEnglishAndRequiredInFrench() {
        // The same input, opposite verdicts — the clearest case for routing
        // rules by language rather than parameterising one rule set.
        XCTAssertTrue(pnames("Ship it now !", dialect: .american)
            .contains(.spaceBeforePunctuation))
        XCTAssertFalse(pnames("Envoyez-le maintenant\u{202F}!", dialect: .french)
            .contains(.frenchSpacing))
    }

    func testPluginsDeclareTheirLanguages() {
        for plugin in CheckEngine.englishPlugins {
            XCTAssertEqual(plugin.languages, [.english], plugin.identifier)
        }
        for plugin in CheckEngine.frenchPlugins {
            XCTAssertEqual(plugin.languages, [.french], plugin.identifier)
        }
    }

    // MARK: - Detection

    func testDetectsFrench() {
        XCTAssertEqual(LanguageDetector.detect(
            in: "Le rapport est prêt et nous allons le relire demain matin."), .french)
    }

    func testDetectsEnglish() {
        XCTAssertEqual(LanguageDetector.detect(
            in: "The report is ready and we will review it tomorrow morning."), .english)
    }

    func testShortTextFallsBackRatherThanGuessing() {
        XCTAssertEqual(LanguageDetector.detect(in: "ok"), .english)
    }

    func testAutoDialectResolvesBeforeChecking() {
        let result = CheckEngine().check(text: "Le probleme est tres grave.", dialect: .auto)
        XCTAssertEqual(result.language, .french)
        XCTAssertEqual(result.dialect, .french)
    }

    func testDialectsMapToLanguages() {
        XCTAssertEqual(Dialect.british.language, .english)
        XCTAssertEqual(Dialect.canadianFrench.language, .french)
        XCTAssertEqual(Dialect.default(for: .french), .french)
    }

    // MARK: - Orthographe

    func testAccentCorrection() {
        let found = alerts("Le probleme est reel.", features: .spelling)
        XCTAssertTrue(found.contains { $0.replacements.first == "problème" })
    }

    func testAccentCorrectionPreservesCapitalisation() {
        let found = alerts("Tres bien.", features: .spelling)
        XCTAssertEqual(found.first?.replacements.first, "Très")
    }

    func testCorrectFrenchProducesNoSpellingAlert() {
        XCTAssertTrue(alerts("Le problème est très grave.", features: .spelling).isEmpty)
    }

    func testRepeatedWordInFrench() {
        XCTAssertTrue(pnames("Il a vu le le chat.", features: .spelling)
            .contains(.repeatedWord))
    }

    // MARK: - Grammaire

    func testElision() {
        let found = alerts("Le ami de Marie.", features: .grammar)
        XCTAssertTrue(found.contains { $0.pname == .elision })
        XCTAssertEqual(found.first { $0.pname == .elision }? .replacements.first, "L'")
    }

    func testElisionNotFlaggedBeforeConsonant() {
        XCTAssertFalse(pnames("Le chat dort.", features: .grammar).contains(.elision))
    }

    func testElisionSkipsHBecauseAspirationIsUndecidable() {
        // "l'homme" elides, "le héros" does not, and nothing in the text says
        // which — so the rule stays silent rather than guessing.
        XCTAssertFalse(pnames("Le heros arrive.", features: .grammar).contains(.elision))
    }

    func testNoConditionalAfterSi() {
        let found = alerts("Si j'aurais su, je serais venu.", features: .grammar)
        let alert = found.first { $0.pname == .conditionalAfterSi }
        XCTAssertNotNil(alert)
        XCTAssertEqual(alert?.replacements.first, "avais")
    }

    func testConditionalElsewhereIsFine() {
        XCTAssertFalse(pnames("Je serais ravi de venir.", features: .grammar)
            .contains(.conditionalAfterSi))
    }

    func testMalgreQue() {
        XCTAssertTrue(pnames("Malgré que ce soit tard.", features: .grammar)
            .contains(.malgreQue))
    }

    func testPallierA() {
        let found = alerts("Il faut pallier à ce manque.", features: .grammar)
        XCTAssertTrue(found.contains { $0.pname == .pallierA })
    }

    func testSentenceCapitalisationInFrench() {
        XCTAssertTrue(pnames("le chat dort.", features: .grammar)
            .contains(.lowercaseSentenceStart))
    }

    // MARK: - Typographie

    func testMissingSpaceBeforeDoublePunctuation() {
        let found = alerts("Vraiment? Oui!", features: .punctuation)
        XCTAssertEqual(found.filter { $0.pname == .frenchSpacing }.count, 2)
        XCTAssertEqual(found.first { $0.pname == .frenchSpacing }? .replacements.first,
                       Typography.narrowNoBreakSpace)
    }

    func testColonTakesTheWiderNoBreakSpace() {
        let found = alerts("Voici:un exemple.", features: .punctuation)
        XCTAssertEqual(found.first { $0.pname == .frenchSpacing }? .replacements.first,
                       Typography.noBreakSpace)
    }

    func testBreakingSpaceIsUpgradedToNonBreaking() {
        let found = alerts("Vraiment ?", features: .punctuation)
        let alert = found.first { $0.pname == .frenchSpacing }
        XCTAssertNotNil(alert)
        XCTAssertEqual(alert?.replacements.first, Typography.narrowNoBreakSpace)
    }

    func testCorrectNonBreakingSpaceIsNotFlagged() {
        XCTAssertFalse(pnames("Vraiment\u{202F}?", features: .punctuation)
            .contains(.frenchSpacing))
    }

    func testTimeOfDayIsNotTreatedAsPunctuation() {
        XCTAssertFalse(pnames("Rendez-vous à 14:30 demain.", features: .punctuation)
            .contains(.frenchSpacing))
    }

    func testURLColonIsNotTreatedAsPunctuation() {
        XCTAssertFalse(pnames("Voir https://exemple.fr pour la suite.",
                              features: .punctuation).contains(.frenchSpacing))
    }

    func testOnlyFirstMarkOfARunIsFlagged() {
        XCTAssertEqual(alerts("Quoi?!", features: .punctuation)
            .filter { $0.pname == .frenchSpacing }.count, 1)
    }

    func testGuillemets() {
        let found = alerts("Il a dit \"bonjour\" hier.", features: .styleGuide)
        let quotes = found.filter { $0.pname == .frenchQuotes }
        XCTAssertEqual(quotes.count, 2)
        XCTAssertTrue(quotes[0].replacements[0].hasPrefix("\u{00AB}"), "premier = ouvrant")
        XCTAssertTrue(quotes[1].replacements[0].hasSuffix("\u{00BB}"), "second = fermant")
    }

    func testClosingGuillemetStaysClosingOncePartiallyApplied() {
        // Regression: deciding open/close by counting straight quotes breaks
        // after the opening one has been converted — the survivor became
        // "the first quote" and was reopened.
        let found = alerts("Il a dit \u{00AB}\u{00A0}bonjour\" hier.", features: .styleGuide)
        let quote = found.first { $0.pname == .frenchQuotes }
        XCTAssertNotNil(quote)
        XCTAssertTrue(quote!.replacements[0].hasSuffix("\u{00BB}"),
                      "doit rester fermant, obtenu: \(quote!.replacements[0].debugDescription)")
    }

    func testTypographicApostrophe() {
        let found = alerts("C'est l'heure.", features: .styleGuide)
        XCTAssertTrue(found.contains { $0.pname == .typographicApostrophe })
        XCTAssertEqual(found.first { $0.pname == .typographicApostrophe }? .replacements.first,
                       Typography.rightSingleQuote)
    }

    func testEtcTakesOnlyOnePeriod() {
        XCTAssertTrue(pnames("des pommes, des poires, etc...", features: .styleGuide)
            .contains(.etcEllipsis))
    }

    // MARK: - Clarté et engagement

    func testFrenchWordyPhrase() {
        let found = alerts("En raison du fait que nous partons.", features: .clarity)
        XCTAssertEqual(found.first { $0.pname == .wordiness }? .replacements.first,
                       "parce que")
    }

    func testFrenchPassiveVoiceNeedsAnAgent() {
        XCTAssertTrue(pnames("Le rapport a été écrit par Sam.", features: .clarity)
            .contains(.passiveVoice))
        // Without "par" it is more likely a plain adjective, so stay silent.
        XCTAssertFalse(pnames("La porte est fermée.", features: .clarity)
            .contains(.passiveVoice))
    }

    func testFrenchFillerAndIntensifier() {
        XCTAssertTrue(pnames("C'est vraiment bien.", features: .engagement)
            .contains(.fillerWord))
        XCTAssertTrue(pnames("C'est très bien.", features: .engagement)
            .contains(.weakIntensifier))
    }

    func testFrenchInclusiveLanguage() {
        XCTAssertTrue(pnames("Bonjour mademoiselle.", features: .inclusivity)
            .contains(.inclusiveLanguage))
    }

    // MARK: - Offsets

    func testFrenchOffsetsSurviveAccentsAndApostrophes() {
        let text = "L'équipe a dit: « très bien » — déjà prêt ?"
        for alert in alerts(text) {
            XCTAssertGreaterThanOrEqual(alert.begin, 0)
            XCTAssertLessThanOrEqual(alert.end, text.utf16.count)
            XCTAssertLessThanOrEqual(alert.begin, alert.end)
        }
    }

    func testAccentedReplacementLandsOnTheRightSpan() {
        let text = "Le probleme arrive."
        let alert = alerts(text, features: .spelling).first { $0.pname == .misspelled }
        XCTAssertNotNil(alert)
        XCTAssertEqual(text.utf16Slice(alert!.begin, alert!.end), "probleme")
    }
}

final class FrenchTokenizerTests: XCTestCase {

    func testApostropheSplitsWordsInFrench() {
        // Elision: "l'ami" is the article plus the noun, so the noun must be
        // reachable as its own token or no rule can ever see it.
        XCTAssertEqual(Tokenizer.words(in: "l'ami", language: .french).map(\.text),
                       ["l", "ami"])
    }

    func testApostropheJoinsWordsInEnglish() {
        XCTAssertEqual(Tokenizer.words(in: "don't", language: .english).map(\.text),
                       ["don't"])
    }

    func testFrenchTokenOffsetsAreCorrectAfterSplit() {
        let tokens = Tokenizer.words(in: "l'ami", language: .french)
        XCTAssertEqual(tokens[1].begin, 2)
        XCTAssertEqual(tokens[1].end, 5)
    }

    func testFrenchSyllablesCountAccentedVowels() {
        XCTAssertEqual(Tokenizer.syllableCount("été", language: .french), 2)
        XCTAssertEqual(Tokenizer.syllableCount("porte", language: .french), 1)
    }

    func testFrenchReadabilityUsesItsOwnFormula() {
        // Needs text dense enough that neither formula clamps at 100, or the
        // two constants cannot be told apart.
        let text = "L'implémentation de cette fonctionnalité nécessite une "
                 + "compréhension approfondie des mécanismes sous-jacents de "
                 + "l'architecture distribuée."
        let asFrench = TextStats.compute(for: text, language: .french)
        let asEnglish = TextStats.compute(for: text, language: .english)
        XCTAssertNotEqual(asFrench.readabilityScore, asEnglish.readabilityScore)
        // Kandel & Moles penalise syllables less, so French scores higher on
        // the same polysyllabic text.
        XCTAssertGreaterThan(asFrench.readabilityScore, asEnglish.readabilityScore)
    }

    func testRarityIsRelativeToTheLanguage() {
        let text = "Le chat dort sur le tapis avec nous."
        // Scored against the English stop list, ordinary French words all look
        // rare; against the French one they do not.
        XCTAssertLessThan(TextStats.compute(for: text, language: .french).rareWords,
                          TextStats.compute(for: text, language: .english).rareWords)
    }
}

/// The spelling-knowledge layer.
///
/// Only the deterministic parts are asserted here. The system dictionary's
/// vocabulary belongs to macOS and will change between releases, so the tests
/// cover the table, the composition rules and the filters — not what Apple
/// happens to know this month.
final class SpellDictionaryTests: XCTestCase {

    private func tokens(_ text: String, _ language: Language = .english) -> [Token] {
        Tokenizer.words(in: text, language: language)
    }

    func testTableFindsItsOwnEntries() {
        let found = TableSpellDictionary.standard.misspellings(
            in: "teh cat", tokens: tokens("teh cat"), language: .english, dialect: .american)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.suggestions.first, "the")
        XCTAssertEqual(found.first?.begin, 0)
        XCTAssertEqual(found.first?.end, 3)
    }

    func testTablePreservesCapitalisation() {
        let found = TableSpellDictionary.standard.misspellings(
            in: "Teh cat", tokens: tokens("Teh cat"), language: .english, dialect: .american)
        XCTAssertEqual(found.first?.suggestions.first, "The")
    }

    func testTableIsLanguageScoped() {
        // "tres" is a French table entry; it must not fire on English text.
        XCTAssertTrue(TableSpellDictionary.standard.misspellings(
            in: "tres", tokens: tokens("tres"), language: .english, dialect: .american).isEmpty)
        XCTAssertFalse(TableSpellDictionary.standard.misspellings(
            in: "tres", tokens: tokens("tres", .french), language: .french, dialect: .french).isEmpty)
    }

    func testCompositePrefersThePrimary() {
        // Where the curated table has an opinion it wins, because it was
        // written for that specific confusion.
        let table = TableSpellDictionary(corrections: [.english: ["teh": "the"]])
        let other = TableSpellDictionary(corrections: [.english: ["teh": "WRONG"]])
        let composite = CompositeSpellDictionary(primary: table, fallback: other)
        let found = composite.misspellings(in: "teh", tokens: tokens("teh"),
                                           language: .english, dialect: .american)
        XCTAssertEqual(found.count, 1, "the same span must not be reported twice")
        XCTAssertEqual(found.first?.suggestions.first, "the")
    }

    func testCompositeKeepsFallbackFindingsElsewhere() {
        let table = TableSpellDictionary(corrections: [.english: ["teh": "the"]])
        let other = TableSpellDictionary(corrections: [.english: ["recieve": "receive"]])
        let composite = CompositeSpellDictionary(primary: table, fallback: other)
        let found = composite.misspellings(in: "teh recieve",
                                           tokens: tokens("teh recieve"),
                                           language: .english, dialect: .american)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found.map(\.begin), [0, 4], "results stay in document order")
    }

    func testAcronymsAndNumbersAreNotFlagged() {
        XCTAssertFalse(SystemSpellDictionary.isWorthFlagging("a"))
        XCTAssertFalse(SystemSpellDictionary.isWorthFlagging("HTTP"))
        XCTAssertFalse(SystemSpellDictionary.isWorthFlagging("v2beta"))
        XCTAssertTrue(SystemSpellDictionary.isWorthFlagging("recieve"))
    }

    func testRegionalDictionaryIsPreferredWhenInstalled() {
        XCTAssertEqual(
            SystemSpellDictionary.resolvedCode(for: .british, language: .english,
                                               available: ["en", "en_GB", "fr"]),
            "en_GB")
        XCTAssertEqual(
            SystemSpellDictionary.resolvedCode(for: .canadianFrench, language: .french,
                                               available: ["en", "fr", "fr_CA"]),
            "fr_CA")
    }

    func testMissingRegionalDictionaryFallsBackToTheLanguage() {
        // The failure this guards against is silent: asking for a code macOS
        // does not have returns no results, which looks exactly like a
        // document with no mistakes in it.
        XCTAssertEqual(
            SystemSpellDictionary.resolvedCode(for: .canadian, language: .english,
                                               available: ["en", "fr"]),
            "en")
        XCTAssertEqual(
            SystemSpellDictionary.resolvedCode(for: .swissFrench, language: .french,
                                               available: ["en", "fr"]),
            "fr")
    }

    func testNoDictionaryAtAllReportsNothingRatherThanGuessing() {
        XCTAssertNil(
            SystemSpellDictionary.resolvedCode(for: .french, language: .french,
                                               available: ["en"]))
    }

    func testEveryDialectHasADistinctCodeWithinItsLanguage() {
        // `auto` is resolved before a context is built, so it shares American
        // English's code by design; every other dialect must be its own.
        let english: [Dialect] = [.american, .british, .canadian, .australian, .indian]
        let french: [Dialect] = [.french, .canadianFrench, .belgianFrench, .swissFrench]
        XCTAssertEqual(Set(english.map(SystemSpellDictionary.code(for:))).count, english.count)
        XCTAssertEqual(Set(french.map(SystemSpellDictionary.code(for:))).count, french.count)
        XCTAssertTrue(french.allSatisfy { SystemSpellDictionary.code(for: $0).hasPrefix("fr") })
    }

    func testCapitalisationOnlySuggestionsAreRejected() {
        // Regression: an unknown loanword came back suggesting itself with a
        // capital, which corrects nothing.
        XCTAssertFalse(SystemSpellDictionary.isUsefulSuggestion("Manpower", for: "manpower"))
        XCTAssertTrue(SystemSpellDictionary.isUsefulSuggestion("receive", for: "recieve"))
    }
}
