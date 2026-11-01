import Foundation
import CorrectorCore

/// Guesses which language a document is written in.
///
/// Detection runs locally and feeds the `auto` dialect, so someone moving
/// between French and English in the same session does not have to move a menu
/// too. An explicit dialect always wins over the guess.
public enum LanguageDetector {

    /// Score each language by how much of the text is its own function words.
    ///
    /// Function words are the right signal because they are the most frequent
    /// tokens in any text and barely overlap between these two languages.
    /// Accented characters break near-ties, since `é`/`è`/`à` are common in
    /// French and essentially absent from English.
    public static func detect(in text: String, default fallback: Language = .english) -> Language {
        let words = Tokenizer.words(in: text, language: .french)
            .map(\.lower)
                .filter { $0.count > 1 }
        // Two words is enough to beat the fallback. A Service user often
        // selects a short phrase, and "c'est tres bien" — three qualifying
        // tokens — was silently falling through to English.
        guard words.count >= 2 else { return fallback }

        var scores: [Language: Double] = [:]
        for language in Language.allCases {
            let stop = Tokenizer.stopWords[language] ?? []
            let hits = words.filter { stop.contains($0) }.count
            scores[language] = Double(hits) / Double(words.count)
        }

        let accented = text.unicodeScalars.filter {
            "àâäçéèêëîïôöùûüÿœæ".unicodeScalars.contains($0)
        }.count
        if accented > 0 {
            scores[.french, default: 0] += min(0.25, Double(accented) / Double(words.count))
        }

        guard let best = scores.max(by: { $0.value < $1.value }), best.value > 0.04 else {
            return fallback
        }
        return best.key
    }
}
