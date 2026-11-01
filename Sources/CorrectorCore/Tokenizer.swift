import Foundation
import CorrectorDelta

/// A word and the UTF-16 span it occupies.
public struct Token: Equatable, Sendable {
    public let text: String
    public let begin: Int
    public let end: Int
    public init(text: String, begin: Int, end: Int) {
        self.text = text; self.begin = begin; self.end = end
    }
    public var lower: String { text.lowercased() }
}

/// Word and sentence segmentation over UTF-16 offsets.
///
/// Every offset this produces feeds straight into `Alert.begin`/`end`, so the
/// tokenizer counts in UTF-16 code units throughout.
public enum Tokenizer {

    /// Characters that may appear inside a word.
    ///
    /// Whether an apostrophe binds or separates is a property of the language
    /// (see `Language.apostropheJoinsWords`): English `don't` is one word,
    /// French `l'ami` is two.
    static func isWordScalar(_ ch: Character, _ language: Language) -> Bool {
        if ch.isLetter || ch.isNumber || ch == "-" { return true }
        if ch == "'" || ch == "\u{2019}" { return language.apostropheJoinsWords }
        return false
    }

    public static func words(in text: String, language: Language = .english) -> [Token] {
        var tokens: [Token] = []
        var offset = 0
        var start = 0
        var current = ""

        for ch in text {
            let width = String(ch).utf16Length
            if isWordScalar(ch, language) {
                if current.isEmpty { start = offset }
                current.append(ch)
            } else if !current.isEmpty {
                tokens.append(trim(Token(text: current, begin: start, end: offset)))
                current = ""
            }
            offset += width
        }
        if !current.isEmpty {
            tokens.append(trim(Token(text: current, begin: start, end: offset)))
        }
        return tokens.filter { !$0.text.isEmpty }
    }

    /// Strip leading/trailing apostrophes and hyphens that segmentation may
    /// have swept into the token (e.g. `"well-"` at a line break).
    private static func trim(_ token: Token) -> Token {
        var text = token.text
        var begin = token.begin
        var end = token.end
        while let f = text.first, f == "'" || f == "\u{2019}" || f == "-" {
            text.removeFirst(); begin += 1
        }
        while let l = text.last, l == "'" || l == "\u{2019}" || l == "-" {
            text.removeLast(); end -= 1
        }
        return Token(text: text, begin: begin, end: end)
    }

    /// Sentence spans as half-open UTF-16 ranges.
    ///
    /// A sentence ends at terminal punctuation followed by whitespace, or at a
    /// blank line. Scanning the UTF-16 view directly keeps the offsets in the
    /// same units the alert schema uses; every character
    /// this looks for is ASCII and therefore exactly one code unit wide, so no
    /// width bookkeeping is needed.
    public static func sentences(in text: String) -> [(begin: Int, end: Int)] {
        let units = Array(text.utf16)
        let space: UInt16 = 32, tab: UInt16 = 9, newline: UInt16 = 10, carriage: UInt16 = 13
        let dot: UInt16 = 46, bang: UInt16 = 33, query: UInt16 = 63

        func isSpace(_ u: UInt16) -> Bool {
            u == space || u == tab || u == newline || u == carriage
        }
        func isTerminator(_ u: UInt16) -> Bool { u == dot || u == bang || u == query }

        var spans: [(begin: Int, end: Int)] = []
        var start = 0
        var lastContent = -1
        var index = 0

        func closeSpan() {
            if lastContent >= start { spans.append((begin: start, end: lastContent + 1)) }
            lastContent = -1
        }

        while index < units.count {
            let unit = units[index]
            if !isSpace(unit) { lastContent = index }

            if isTerminator(unit) {
                // Consume a run such as "?!" or "...".
                var last = index
                while last + 1 < units.count, isTerminator(units[last + 1]) { last += 1 }
                if last + 1 >= units.count || isSpace(units[last + 1]) {
                    lastContent = last
                    closeSpan()
                    index = last + 1
                    while index < units.count, isSpace(units[index]) { index += 1 }
                    start = index
                    continue
                }
                index = last + 1
                continue
            }

            if unit == newline {
                // A blank line ends the sentence even without punctuation.
                var last = index
                var newlines = 1
                while last + 1 < units.count, isSpace(units[last + 1]) {
                    last += 1
                    if units[last] == newline { newlines += 1 }
                }
                if newlines >= 2 {
                    closeSpan()
                    index = last + 1
                    start = index
                    continue
                }
                index = last + 1
                continue
            }
            index += 1
        }
        closeSpan()
        return spans
    }

    /// Rough syllable count, used only for the readability formula.
    ///
    /// Both languages count vowel groups, but French needs the accented vowels
    /// in the vowel set, and its final `e` is silent far more consistently than
    /// English's — compare "porte" (1 syllable) with English "resume" (3).
    public static func syllableCount(_ word: String, language: Language = .english) -> Int {
        let vowels: Set<Character> = language == .french
            ? Set("aeiouyàâäéèêëîïôöùûüÿœæ")
: Set("aeiouy")
        let lowered = word.lowercased()

        var count = 0
        var previousWasVowel = false
        for ch in lowered {
            let isVowel = vowels.contains(ch)
            if isVowel, !previousWasVowel { count += 1 }
            previousWasVowel = isVowel
        }

        switch language {
        case.english:
            if lowered.count > 2, lowered.hasSuffix("e"), count > 1 { count -= 1 }
        case.french:
            // Silent final -e, -es and -ent (the third-person plural ending).
            if count > 1 {
                if lowered.hasSuffix("ent"), lowered.count > 4 { count -= 1 }
                else if lowered.hasSuffix("es") || lowered.hasSuffix("e") { count -= 1 }
            }
        }
        return max(1, count)
    }

    /// Frequency-ranked function words, used to guess a document's language.
    public static let stopWords: [Language: Set<String>] = [
        .english: ["the", "and", "of", "to", "in", "is", "that", "it", "for",
                   "with", "as", "was", "on", "are", "this", "be", "have",
                   "from", "at", "by", "not", "but", "what", "they", "we"],
                       .french: ["le", "la", "les", "de", "des", "du", "et", "un", "une",
                  "est", "que", "qui", "dans", "pour", "pas", "sur", "ne",
                  "nous", "vous", "plus", "au", "aux", "ce", "sont", "avec",
                  "il", "elle", "nous", "mais", "ou", "son", "ses", "leur"],
    ]

    /// Closed-class words for the requested language, used to estimate
    /// "rare word" density. A word being rare is relative to its own language,
    /// so French text scored against the English list would read as almost
    /// entirely rare.
    public static func commonWords(for language: Language) -> Set<String> {
        switch language {
        case.english: return commonWords
        case.french:  return commonWordsFrench
        }
    }

    /// Small closed-class list used to estimate "rare word" density.
    public static let commonWords: Set<String> = [
        "the","be","to","of","and","a","in","that","have","i","it","for","not","on","with",
        "he","as","you","do","at","this","but","his","by","from","they","we","say","her",
        "she","or","an","will","my","one","all","would","there","their","what","so","up",
        "out","if","about","who","get","which","go","me","when","make","can","like","time",
        "no","just","him","know","take","people","into","year","your","good","some","could",
        "them","see","other","than","then","now","look","only","come","its","over","think",
        "also","back","after","use","two","how","our","work","first","well","way","even",
        "new","want","because","any","these","give","day","most","us","is","are","was",
        "were","been","has","had","did","very","much","more","such","own","same","too",
    ]

    public static let commonWordsFrench: Set<String> = [
        "le","la","les","un","une","des","du","de","d","l","au","aux",
        "et","ou","mais","donc","or","ni","car","que","qui","quoi","dont","où",
        "ce","cet","cette","ces","se","sa","son","ses","leur","leurs",
        "je","tu","il","elle","on","nous","vous","ils","elles","me","te","lui","y","en",
        "mon","ma","mes","ton","ta","tes","notre","votre","nos","vos",
        "est","sont","était","étaient","été","être","suis","es","sommes","êtes",
        "a","ai","as","ont","avait","avaient","avoir","eu","avons","avez",
        "pas","ne","plus","moins","très","bien","aussi","tout","tous","toute","toutes",
        "dans","sur","sous","pour","par","avec","sans","chez","vers","entre","depuis",
        "comme","si","quand","alors","ainsi","encore","déjà","toujours","jamais",
        "faire","fait","peut","peuvent","doit","doivent","va","vont","dit","dire",
        "cela","ça","ceci","celui","celle","ceux","autre","autres","même","mêmes",
        "il","y","a","on","nous","leur","quel","quelle","quels","quelles",
    ]
}
