import SwiftUI
import AppKit
import CorrectorCore
import CorrectorEngine
import CorrectorSession
import CorrectorAppCore

/// Corrector's macOS application.
///
/// A real window rather than a menu-bar-only agent: Corrector holds a document
/// of its own, and a document needs somewhere to be read. The menu-bar item
/// stays alongside it, mirroring the live score, because the window is usually
/// behind whatever is being written in.
@main
struct CorrectorAppMain: App {
    @StateObject private var model = DocumentModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Corrector", id: CorrectorAppMain.mainWindowID) {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 560)
        }
            .defaultSize(width: 1080, height: 700)
                .commands {
            CommandGroup(replacing: .newItem) {
                Button(model.strings.newDocument) { model.newDocument() }
                    .keyboardShortcut("n")
                Button(model.strings.open) { open() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .pasteboard) {
                // Fixed title on purpose: SwiftUI does not re-evaluate
                // `.commands` when observed state changes, so a title that
                // switched between "copy selection" and "copy all" would go
                // stale. The toolbar button, which does refresh, carries the
                // dynamic wording.
                Button(model.strings.copy) { model.copySelection() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            CommandMenu(model.strings.checkMenu) {
                Button(model.strings.checkNow) { model.checkNow() }
                    .keyboardShortcut("r")
                Button(model.strings.acceptAll) { model.acceptAll() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarPanel(model: model)
        } label: {
            Label("\(model.scores.generalScore)", systemImage: "checkmark.seal")
        }
            .menuBarExtraStyle(.menu)
    }

    /// Identifier the menu-bar item uses to bring the window back.
    static let mainWindowID = "corrector.main"

    private func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.load(from: url) }
    }
}

private struct MenuBarPanel: View {
    @ObservedObject var model: DocumentModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Closing the last window leaves the app running with nothing on
        // screen and no way back, so the menu-bar item always offers one.
        Button(model.strings.showWindow) {
            openWindow(id: CorrectorAppMain.mainWindowID)
            AppDelegate.showMainWindow()
        }
        Divider()
        if let status = model.status {
            Text(status)
            Divider()
        }
        Text("Score \(model.scores.generalScore)/100")
        Text("\(model.alerts.count) \(model.alerts.count == 1 ? model.strings.suggestionCount : model.strings.suggestionsCount)")
        Divider()
        Button(model.strings.copyAll) { model.copySelection() }
            .disabled(model.text.isEmpty)
        Button(model.strings.acceptAll) { model.acceptAll() }
            .disabled(!model.alerts.contains { !$0.replacements.isEmpty })
        Divider()
        Button(model.strings.quit) { NSApplication.shared.terminate(nil) }
    }
}

/// Editor on the left, suggestions and scores on the right. Side by side
/// rather than stacked, so accepting a suggestion never moves the text the eye
/// is already on.
struct ContentView: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                EditorView(text: $model.text,
                           alerts: model.alerts,
                           selectedID: model.selectedAlertID,
                           onSelect: { model.select($0) },
                           onSelectionChange: { model.selection = $0 })
                Divider()
                footer
            }
                .frame(minWidth: 420)

            VStack(spacing: Metric.lg) {
                ScoreView(scores: model.scores, counts: model.alertCounts,
                          strings: model.strings)
                StatsView(stats: model.stats, strings: model.strings)
                Divider()
                CardsView(model: model)
            }
                .padding(.horizontal, Metric.lg)
                    .padding(.top, Metric.lg)
                        .frame(minWidth: 330, idealWidth: 380)
                            .background(Color(nsColor: .windowBackgroundColor))
        }
            .toolbar {
            ToolbarItemGroup {
                // Dialect and the enabled check set are the two halves of the
                // capability handshake.
                // Document dialect, grouped by language. `auto` first, since
                // detection is the sensible default for a mixed workflow.
                Picker(model.strings.dialect, selection: $model.dialect) {
                    Text(model.strings.detectAutomatically).tag(Dialect.auto)
                    Divider()
                    ForEach(Dialect.allCases.filter { $0.language == .english && $0 != .auto },
                            id: \.self) { Text($0.displayName).tag($0) }
                    Divider()
                    ForEach(Dialect.allCases.filter { $0.language == .french },
                            id: \.self) { Text($0.displayName).tag($0) }
                }
                    .pickerStyle(.menu)
                        .frame(width: 190)

                Menu {
                    ForEach(FeatureToggle.all(model.uiLocale), id: \.label) { toggle in
                        Button {
                            model.enabledFeatures.formSymmetricDifference(toggle.feature)
                        } label: {
                            Label(toggle.label,
                                  systemImage: model.enabledFeatures.contains(toggle.feature)
                                      ? "checkmark.circle.fill": "circle")
                        }
                    }
                } label: {
                    Label(model.strings.checks, systemImage: "slider.horizontal.3")
                }

                Picker(model.strings.interfaceLanguage, selection: $model.uiLocale) {
                    ForEach(UILocale.allCases) { Text($0.displayName).tag($0) }
                }
                    .pickerStyle(.menu)
                        .frame(width: 110)

                // Copying is the usual last step after accepting suggestions,
                // so it earns a place in the toolbar rather than only a shortcut.
                Button {
                    model.copySelection()
                } label: {
                    Label(model.didJustCopy
                            ? model.strings.copied
                            : (model.copiesWholeDocument
                                ? model.strings.copyAll
                                : model.strings.copySelection),
                          systemImage: model.didJustCopy ? "checkmark" : "doc.on.doc")
                }
                .help(model.copiesWholeDocument
                        ? model.strings.copyAll
                        : model.strings.copySelection)
                .disabled(model.text.isEmpty)

                Button {
                    model.acceptAll()
                } label: {
                    Label(model.strings.acceptAll, systemImage: "checkmark.circle")
                }
                    .disabled(!model.alerts.contains { !$0.replacements.isEmpty })
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Metric.lg) {
            Text(model.strings.wordCount(model.stats.words))
            Text(model.strings.sentenceCount(model.stats.sentences))
            // Which language the engine resolved to, so `auto` is never opaque.
            Text(model.strings.languageName(model.detectedLanguage))
                .foregroundStyle(.tertiary)
            Spacer()
            VersionBadge(strings: model.strings, revision: model.revision)
            Text(model.strings.suggestionCount(model.alerts.count))
        }
            .font(.caption2)
                .foregroundStyle(.secondary)
                    .padding(.horizontal, Metric.lg)
                        .padding(.vertical, Metric.md)
    }
}

/// The version in the footer, and what it opens on hover.
///
/// What stood here was `rev \(model.revision)` — the *document's* edit
/// counter, which climbs as you type. Reading "version 47" after forty-seven
/// keystrokes would have been worse than the original label, so this shows the
/// build and keeps the revision inside the popover, where a number that means
/// something only to the engine belongs.
struct VersionBadge: View {
    let strings: Strings
    let revision: Int

    @State private var isShowing = false
    /// Hovering the popover does not keep the badge's own hover alive — the
    /// popover is a separate window — so a close is scheduled and cancelled
    /// rather than acted on immediately. Without this the panel snaps shut
    /// the moment the pointer moves towards it.
    @State private var closeTask: Task<Void, Never>?

    var body: some View {
        Text("\(strings.version) \(Release.display)")
            .onHover { inside in
                if inside { open() } else { scheduleClose() }
            }
            .popover(isPresented: $isShowing, arrowEdge: .top) {
                ReleaseNotesView(strings: strings, revision: revision)
                    .onHover { inside in
                        if inside { open() } else { scheduleClose() }
                    }
            }
    }

    private func open() {
        closeTask?.cancel()
        closeTask = nil
        isShowing = true
    }

    private func scheduleClose() {
        closeTask?.cancel()
        closeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isShowing = false
        }
    }
}

/// What changed in this build.
struct ReleaseNotesView: View {
    let strings: Strings
    let revision: Int

    private var features: [Release.Note] { Release.notes.filter { $0.kind == .feature } }
    private var fixes: [Release.Note] { Release.notes.filter { $0.kind == .fix } }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.md) {
            HStack(spacing: Metric.sm) {
                Text("Corrector").font(.headline)
                Text(Release.display)
                    .font(.caption)
                    .padding(.horizontal, Metric.sm)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15),
                                in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            Divider()

            section(strings.newFeatures, features)
            if !fixes.isEmpty {
                section(strings.bugFixes, fixes)
            }

            Divider()
            Text(strings.documentRevision(revision))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
            .padding(Metric.lg)
                .frame(width: 360)
    }

    private func section(_ title: String, _ notes: [Release.Note]) -> some View {
        VStack(alignment: .leading, spacing: Metric.sm) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(notes) { note in
                HStack(alignment: .firstTextBaseline, spacing: Metric.sm) {
                    Image(systemName: note.kind.symbol)
                        .font(.caption2)
                        .foregroundStyle(note.kind == .feature ? Color.accentColor : .secondary)
                        .frame(width: 14)
                    Text(note.text(strings.locale))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct FeatureToggle {
    let label: String
    let feature: FeatureSet

    static func all(_ locale: UILocale) -> [FeatureToggle] {
        let french = locale == .french
        return [
            .init(label: french ? "Orthographe": "Spelling", feature: .spelling),
                .init(label: french ? "Grammaire": "Grammar", feature: .grammar),
                    .init(label: french ? "Ponctuation": "Punctuation", feature: .punctuation),
                        .init(label: french ? "Clarté": "Clarity", feature: .clarity),
                            .init(label: french ? "Engagement": "Engagement", feature: .engagement),
                                .init(label: french ? "Typographie": "Style guide", feature: .styleGuide),
                                    .init(label: french ? "Inclusivité": "Inclusivity", feature: .inclusivity),
        ]
    }
}

/// Reopens the window when the Dock icon is clicked and the app has none.
///
/// A SwiftUI `WindowGroup` does not quit the app when its last window closes,
/// and AppKit will not recreate one by itself — without this the app survives
/// as an invisible process.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = ServiceProvider()

    /// Built lazily: it is main-actor isolated, and a stored property would be
    /// initialised before the delegate is known to be on the main actor.
    private lazy var quickCorrect = QuickCorrect()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Registers the handlers for the Services declared in Info.plist.
        NSApp.servicesProvider = serviceProvider
        // The system-wide shortcut. Needs no permission: a registered hot key
        // only wakes us for this one combination.
        quickCorrect.install()
        // Ask the system to re-read our Services. Without this a freshly built
        // bundle can take minutes, or a logout, to appear in the menu.
        NSUpdateDynamicServices()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        Self.showMainWindow()
        return true
    }

    /// Bring the document window forward, reopening it if it was closed.
    static func showMainWindow() {
        let app = NSApplication.shared
        if let window = app.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        app.activate(ignoringOtherApps: true)
    }
}
