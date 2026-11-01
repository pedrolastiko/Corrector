import Foundation
import CorrectorCore
import CorrectorEngine
import CorrectorSession
import CorrectorDelta

// Corrector — an offline writing assistant for macOS.
//
// This is the command-line front end. It shares every module below it with the
// app target, which is why a rule can be developed and asserted on here and
// then appear in the window with no further work. See README.md.

var strings = CLIStrings(locale: .system)

// MARK: - Argument parsing

struct Options {
    var command = ""
    var path: String?
    var json = false
    var cards = false
    var transient = false
    var dialect: Dialect = .auto
    var features: FeatureSet = .all
    var uiLocale: CLILocale = .system
}

func parse(_ argv: [String]) -> Options? {
    var options = Options()
    var rest = argv.dropFirst()
    guard let command = rest.first else { return nil }
    options.command = command
    rest = rest.dropFirst()

    var iterator = Array(rest).makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--json": options.json = true
        case "--cards": options.cards = true
        case "--transient": options.transient = true
        case "--no-color": Render.useColor = false
        case "--ui":
            guard let value = iterator.next(),
                  let locale = CLILocale(rawValue: value.lowercased()) else {
                FileHandle.standardError.write(Data(
                    "error: --ui expects english or french\n".utf8))
                exit(2)
            }
            options.uiLocale = locale
        case "-h", "--help": return nil
        case "--dialect":
            guard let value = iterator.next(), let d = Dialect(rawValue: value) else {
                FileHandle.standardError.write(Data(
                    ("error: --dialect expects one of: "
                     + Dialect.allCases.map(\.rawValue).joined(separator: ", ")
                     + "\n").utf8))
                exit(2)
            }
            options.dialect = d
        case "--language":
            guard let value = iterator.next(),
                  let language = Language(rawValue: value.lowercased()) else {
                FileHandle.standardError.write(Data(
                    ("error: --language expects one of: "
                     + Language.allCases.map(\.rawValue).joined(separator: ", ")
                     + "\n").utf8))
                exit(2)
            }
            options.dialect = Dialect.default(for: language)
        case "--only":
            guard let value = iterator.next() else {
                FileHandle.standardError.write(Data("error: --only needs a value\n".utf8))
                exit(2)
            }
            var set: FeatureSet = []
            for name in value.split(separator: ",").map(String.init) {
                switch name.trimmingCharacters(in: .whitespaces).lowercased() {
                case "spelling": set.insert(.spelling)
                case "grammar": set.insert(.grammar)
                case "punctuation": set.insert(.punctuation)
                case "clarity": set.insert(.clarity)
                case "engagement": set.insert(.engagement)
                case "styleguide": set.insert(.styleGuide)
                case "inclusivity": set.insert(.inclusivity)
                default:
                    FileHandle.standardError.write(Data("error: unknown check “\(name)”\n".utf8))
                    exit(2)
                }
            }
            options.features = set
        default:
            if argument.hasPrefix("-"), argument != "-" {
                FileHandle.standardError.write(Data("error: unknown option \(argument)\n".utf8))
                exit(2)
            }
            options.path = argument
        }
    }
    return options
}

// MARK: - Input

func sampleURL(named name: String) -> URL? {
    let base = Bundle.module.resourceURL?.appendingPathComponent("Samples")
    for candidate in [name, name + ".txt"] {
        if let url = base?.appendingPathComponent(candidate),
           FileManager.default.fileExists(atPath: url.path) { return url }
    }
    return nil
}

func loadInput(_ path: String?) -> (text: String, label: String) {
    guard let path else {
        FileHandle.standardError.write(Data("error: no input file (use - for stdin)\n".utf8))
        exit(2)
    }
    if path == "-" {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return (String(decoding: data, as: UTF8.self), "<stdin>")
    }
    if FileManager.default.fileExists(atPath: path),
       let text = try? String(contentsOfFile: path, encoding: .utf8) {
        return (text, path)
    }
    if let url = sampleURL(named: path),
       let text = try? String(contentsOf: url, encoding: .utf8) {
        return (text, "sample:" + url.deletingPathExtension().lastPathComponent)
    }
    FileHandle.standardError.write(Data("error: cannot read “\(path)”\n".utf8))
    exit(2)
}

/// Open a session: construct the handshake, send it, and read the negotiated
/// capabilities back.
func openSession(text: String, label: String, options: Options) -> CheckSession {
    let session = CheckSession(engine: .system(features: options.features))
    let documentID = DocumentID.derive(application: "corrector-cli",
                                       window: label, field: "document")
    let handshake = ClientMessage.StartSession(
        clientSupports: options.features,
        dialect: options.dialect,
        documentIdentifier: documentID.value,
        documentIdentifierIsTransient: options.transient,
        application: "corrector-cli",
        domain: "general",
        text: text)
    session.handle(.startSession(handshake))
    return session
}

// MARK: - Output

func jsonOutput(session: CheckSession, label: String) -> String {
    let alerts = session.alertStore.visibleAlerts
    let stats = TextStats.compute(for: session.text, language: session.language)
    let scores = Scores.compute(alerts: alerts, wordCount: stats.words)

    struct Payload: Encodable {
        let document: String
        let language: String
        let revision: Int
        let scores: Scores
        let stats: TextStats
        let alerts: [Alert]
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let payload = Payload(document: label, language: session.language.rawValue,
                          revision: session.revision,
                          scores: scores, stats: stats, alerts: alerts)
    return String(decoding: (try? encoder.encode(payload)) ?? Data(), as: UTF8.self)
}

func printReport(session: CheckSession, label: String, options: Options) {
    let s = CLIStrings(locale: options.uiLocale)
    let alerts = session.alertStore.visibleAlerts
    let stats = TextStats.compute(for: session.text, language: session.language)
    let scores = Scores.compute(alerts: alerts, wordCount: stats.words)

    print(Render.bold("\n\(label)")
          + Render.dim("  rev \(session.revision)")
          + Render.dim("  ·  \(session.language.displayName)"))
    print(Render.dim(String(repeating: "═", count: 74)))
    print()
    print(Render.document(session.text, alerts: alerts,
                          selected: session.alertStore.selectedID))
    print()
    print(Render.dim(String(repeating: "─", count: 74)))
    print(Render.scorePanel(scores, counts: session.alertStore.cardLayoutGroupCounts(),
                            strings: s))
    print()
    print(Render.dim(String(repeating: "─", count: 74)))

    if alerts.isEmpty {
        print("\n  " + Render.paint(s.noSuggestions, Theme.Palette.teal))
    } else {
        print(Render.bold("\n\(alerts.count) suggestion\(alerts.count == 1 ? "": "s")\n"))
        if options.cards {
            for alert in alerts { print(Render.fullCard(alert, strings: s)); print() }
        } else {
            for (index, alert) in alerts.enumerated() {
                print(Render.miniCard(alert, index: index + 1, strings: s))
            }
        }
    }
    print()
    print(Render.dim(String(repeating: "─", count: 74)))
    print(Render.statsPanel(stats, strings: s))
    print()
}

// MARK: - Commands

func runCheck(_ options: Options) {
    let input = loadInput(options.path)
    let session = openSession(text: input.text, label: input.label, options: options)
    if options.json { print(jsonOutput(session: session, label: input.label)) }
    else { printReport(session: session, label: input.label, options: options) }
}

func runFix(_ options: Options) {
    let input = loadInput(options.path)
    let session = openSession(text: input.text, label: input.label, options: options)
    let applied = session.acceptAll()

    if options.json {
        print(jsonOutput(session: session, label: input.label))
        return
    }
    let remaining = session.alertStore.visibleAlerts.count
    FileHandle.standardError.write(Data(
        (CLIStrings(locale: options.uiLocale).applied(applied, remaining: remaining)
         + "\n").utf8))
    print(session.text, terminator: "")
}

func runStats(_ options: Options) {
    let input = loadInput(options.path)
    let language = options.dialect == .auto
        ? LanguageDetector.detect(in: input.text)
: options.dialect.language
    let stats = TextStats.compute(for: input.text, language: language)
    if options.json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: (try? encoder.encode(stats)) ?? Data(), as: UTF8.self))
    } else {
        print(Render.bold("\n\(input.label)")
              + Render.dim("  ·  \(language.displayName)"))
        print(Render.dim(String(repeating: "─", count: 74)))
        print(Render.statsPanel(stats, strings: CLIStrings(locale: options.uiLocale)))
        print()
    }
}

func runSamples() {
    guard let base = Bundle.module.resourceURL?.appendingPathComponent("Samples"),
          let names = try? FileManager.default.contentsOfDirectory(atPath: base.path)
    else { print("no samples bundled"); return }
    print(Render.bold("\n" + CLIStrings(locale: .system).bundledSamples + "\n"))
    for name in names.sorted() where name.hasSuffix(".txt") {
        let url = base.appendingPathComponent(name)
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let stats = TextStats.compute(for: text)
        print("  " + Render.bold(String(name.dropLast(4)).padding(toLength: 16,
                                                                   withPad: " ", startingAt: 0))
              + Render.dim("\(stats.words) \(CLIStrings(locale: .system).words), "
                           + "\(stats.sentences) \(CLIStrings(locale: .system).sentences)"))
    }
    print("\n" + Render.dim("  corrector check memo --cards") + "\n")
}

/// Walkthrough of the architecture: a live edit, a stale-revision rebase, and
/// an accepted suggestion.
func runDemo() {
    print(Render.bold("\nCorrector — architecture walkthrough"))
    print(Render.dim(String(repeating: "═", count: 74)))

    let session = CheckSession()
    let documentID = DocumentID.derive(application: "corrector-cli",
                                       window: "demo", field: "document")

    print("\n" + Render.bold("1. Handshake") + Render.dim(""))
    let replies = session.handle(.startSession(.init(
        clientSupports: .all,
        documentIdentifier: documentID.value,
        text: "teh report was writen by Priya.")))
    for reply in replies {
        if case.started(let started) = reply {
            print("   document id      \(Render.dim(documentID.short + "…"))  "
                  + Render.dim("(SHA-256 of the field, not the text)"))
            print("   session          \(Render.dim(started.sessionUUID.uuidString))")
            print("   max message size \(started.maxMessageSize) bytes  "
                  + Render.dim(""))
        }
    }

    print("\n" + Render.bold("2. First check") + Render.dim(""))
    print("   text      \(session.text.debugDescription)")
    print("   revision  \(session.revision)")
    for alert in session.alertStore.visibleAlerts {
        print("   " + Render.miniCard(alert, index: alert.id % 100,
                                      strings: CLIStrings(locale: .system)))
    }

    print("\n" + Render.bold("3. The user types at the start")
          + Render.dim("  (a changeset, not the full text)"))
    var edit = Delta()
    edit.insert("Yesterday ")
    print("   changeset \(Render.dim(edit.description))")
    let staleAlerts = session.alertStore.visibleAlerts
    session.handle(.submitChangeset(id: 1, revision: session.revision, changeSet: edit))
    print("   revision  \(session.revision)")
    print("   text      \(session.text.debugDescription)")

    print("\n" + Render.bold("4. Stale alerts are rebased, not recomputed from scratch"))
    for old in staleAlerts {
        guard let now = session.alertStore.alert(id: old.id) else { continue }
        print("   \(Render.dim(old.pname.rawValue.padding(toLength: 22, withPad: " ", startingAt: 0)))"
              + "\(old.begin)..<\(old.end)  →  \(now.begin)..<\(now.end)")
    }
    print("   " + Render.dim("positions moved by transformPosition(), §4.3"))

    print("\n" + Render.bold("5. Accept a suggestion") + Render.dim(""))
    if let first = session.alertStore.visibleAlerts.first(where: { !$0.replacements.isEmpty }) {
        print("   accepting \(Render.bold(first.title)): "
              + "\(first.highlightText.debugDescription) → "
              + "\(first.replacements[0].debugDescription)")
        session.accept(alertID: first.id)
        print("   text      \(session.text.debugDescription)")
        print("   revision  \(session.revision)")
    }

    print("\n" + Render.bold("6. Accept the rest"))
    let applied = session.acceptAll()
    print("   applied   \(applied) more")
    print("   result    " + Render.paint(session.text.debugDescription, Theme.Palette.teal))

    let stats = TextStats.compute(for: session.text)
    let scores = Scores.compute(alerts: session.alertStore.visibleAlerts,
                                wordCount: stats.words)
    print("\n" + Render.bold("7. Final score"))
    print(Render.scorePanel(scores, counts: session.alertStore.cardLayoutGroupCounts(),
                            strings: CLIStrings(locale: .system)))
    print()
}

// MARK: - Entry point

guard let options = parse(CommandLine.arguments) else {
    print(strings.usage)
    exit(CommandLine.arguments.count > 1 ? 0 : 1)
}

switch options.command {
case "check":   runCheck(options)
case "fix":     runFix(options)
case "stats":   runStats(options)
case "demo":    runDemo()
case "samples": runSamples()
default:
    FileHandle.standardError.write(Data("error: unknown command “\(options.command)”\n\n".utf8))
    print(strings.usage)
    exit(2)
}
