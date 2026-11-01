import SwiftUI
import AppKit
import Combine
import CorrectorCore
import CorrectorEngine
import CorrectorSession
import CorrectorDelta
import CorrectorAppCore

/// The app's view model: owns a `CheckSession` and republishes its state.
///
/// Implements the editing workflow against a document the user types
/// here, rather than one captured from another application.
@MainActor
final class DocumentModel: ObservableObject {

    @Published var text: String = "" {
        didSet { if !isApplyingProgrammatically { scheduleCheck() } }
    }
    @Published private(set) var alerts: [Alert] = []
    @Published private(set) var scores: Scores = .empty
    @Published private(set) var stats: TextStats = .empty
    @Published private(set) var revision: Int = 0
    @Published var selectedAlertID: Int?
    /// The editor's current selection, mirrored so the toolbar can act on it.
    @Published var selection = Selection(begin: 0, end: 0)
    /// Set briefly after a copy, so the button can confirm it did something.
    @Published private(set) var didJustCopy = false
    /// Transient message shown in the menu-bar item after a quick correction,
    /// since the user is looking at another application at the time.
    @Published private(set) var status: String?
    @Published var expandedAlertID: Int?

    @Published var dialect: Dialect = Preferences.dialect {
        didSet {
            Preferences.dialect = dialect
            rebuildSession()
        }
    }
    /// The interface language, independent of the document's dialect.
    @Published var uiLocale: UILocale = Preferences.uiLocale {
        didSet { Preferences.uiLocale = uiLocale }
    }
    /// The language the engine actually used, after `auto` resolved.
    @Published private(set) var detectedLanguage: Language = .english

    var strings: Strings { Strings(locale: uiLocale) }
    @Published var enabledFeatures: FeatureSet = Preferences.features {
        didSet {
            Preferences.features = enabledFeatures
            session.handle(.toggleChecks(enabledFeatures))
            refresh()
        }
    }

    private var session = CheckSession()
    private var isApplyingProgrammatically = false
    private var checkTask: Task<Void, Never>?

    /// Debounce before rechecking, so a check does not run on every keystroke.
    /// 250 ms is long enough to swallow a burst of typing and short enough that
    /// a pause feels answered.
    private let debounce = Duration.milliseconds(250)

    // Persistence: the document and how far it has been checked, so closing
    // the window is not the same as losing the draft.
    private var store: DocumentStore?
    private let documentID = DocumentID.derive(application: "Corrector",
                                               window: "Editor", field: "document")

    /// Shared instance, so the Services provider and the window operate on the
    /// same document rather than two divergent copies.
    static let shared = DocumentModel()

    init() {
        store = try? DocumentStore.defaultStore()
        startSession(with: restoredText())
        // Write the opening document straight away, so a first launch that is
        // only read and never typed into still restores next time.
        persist()
    }

    /// Last session's text, so the window comes back as it was left.
    private func restoredText() -> String {
        if let saved = try? store?.load(documentID), !saved.text.isEmpty {
            return saved.text
        }
        return DocumentModel.welcomeText(for: uiLocale)
    }

    // MARK: - Session lifecycle

    private func startSession(with initialText: String) {
        session = CheckSession(engine: .system(features: enabledFeatures))
        session.handle(.startSession(.init(
            clientSupports: enabledFeatures,
            dialect: dialect,
            documentIdentifier: documentID.value,
            documentIdentifierIsTransient: false,
            application: "Corrector",
            domain: "general",
            text: initialText)))

        // A fresh session starts with an empty dictionary and mute list, so
        // put the user's saved decisions back before the first check runs.
        session.alertStore.restore(dictionary: Preferences.dictionary,
                                   mutedRules: Preferences.mutedRules)

        isApplyingProgrammatically = true
        text = initialText
        isApplyingProgrammatically = false
        refresh()
    }

    private func rebuildSession() {
        startSession(with: text)
    }

    // MARK: - Checking

    private func scheduleCheck() {
        checkTask?.cancel()
        let pending = text
        checkTask = Task { [weak self] in
            try? await Task.sleep(for: self?.debounce ?? .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.runCheck(on: pending)
        }
    }

    private func runCheck(on newText: String) {
        // The editor hands us whole text; it is diffed into a changeset and
        // submitted against the current revision, so held suggestions are
        // rebased rather than recomputed.
        session.replaceAll(with: newText)
        refresh()
        persist()
    }

    /// Check immediately, skipping the debounce.
    func checkNow() {
        checkTask?.cancel()
        runCheck(on: text)
    }

    private func refresh() {
        alerts = session.alertStore.visibleAlerts
        detectedLanguage = session.language
        stats = TextStats.compute(for: session.text, language: session.language)
        scores = Scores.compute(alerts: alerts, wordCount: stats.words)
        revision = session.revision
        if let selected = selectedAlertID,
           !alerts.contains(where: { $0.id == selected }) {
            selectedAlertID = nil
            expandedAlertID = nil
        }
    }

    private func persist() {
        try? store?.save(StoredDocument(documentID: documentID.value,
                                        text: session.text,
                                        revision: session.revision))
        try? store?.checkpoint(documentID, syncedRevision: session.revision)
    }

    // MARK: - User actions

    func select(_ id: Int?) {
        selectedAlertID = id
        if id != nil { session.handle(.userAction(alertID: id!, action: .view)) }
    }

    func toggleExpanded(_ id: Int) {
        expandedAlertID = (expandedAlertID == id) ? nil : id
        select(id)
    }

    func accept(_ alert: Alert) {
        session.accept(alertID: alert.id)
        pushSessionTextIntoEditor()
    }

    func dismiss(_ alert: Alert) {
        session.handle(.userAction(alertID: alert.id, action: .dismiss))
        refresh()
    }

    func muteRule(of alert: Alert) {
        session.alertStore.mute(rule: alert.pname)
        Preferences.mutedRules = session.alertStore.mutedRules
        refresh()
    }

    func addToDictionary(_ alert: Alert) {
        session.alertStore.addToDictionary(alert.highlightText)
        Preferences.dictionary = session.alertStore.dictionary
        refresh()
    }

    func acceptAll() {
        session.acceptAll()
        pushSessionTextIntoEditor()
    }

    /// The session changed the text; mirror it back without re-triggering a
    /// check of our own edit.
    private func pushSessionTextIntoEditor() {
        isApplyingProgrammatically = true
        text = session.text
        isApplyingProgrammatically = false
        refresh()
        persist()
    }

    /// Copy the selection to the clipboard, or the whole document when nothing
    /// is selected. After accepting suggestions the usual wish is to take the
    /// corrected text away, and demanding a select-all first would be a step
    /// that buys nothing.
    @discardableResult
    func copySelection() -> Int {
        let copied = selection.isCaret
            ? session.text
            : session.text.utf16Slice(selection.begin, selection.end)
        guard !copied.isEmpty else { return 0 }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copied, forType: .string)

        didJustCopy = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            self?.didJustCopy = false
        }
        return copied.utf16Length
    }

    /// Show a short message for a moment.
    func flashStatus(_ message: String) {
        status = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.status = nil
        }
    }

    /// Whether the button should offer "copy all" rather than "copy selection".
    var copiesWholeDocument: Bool { selection.isCaret }

    // MARK: - Documents

    func load(from url: URL) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        startSession(with: contents)
        persist()
    }

    // MARK: - Settings
    //
    // `Preferences` stays the store; these publish a change so the settings
    // screen redraws, and re-run the check so the document agrees with the new
    // decision immediately rather than at the next keystroke.

    /// Bumped whenever a stored preference changes, so SwiftUI redraws lists
    /// that read `Preferences` directly. Cheaper than mirroring three
    /// collections into published properties that could then disagree with the
    /// store they came from.
    @Published private(set) var settingsRevision = 0

    var dictionaryWords: Set<String> { Preferences.dictionary }
    var mutedRules: Set<AlertPname> { Preferences.mutedRules }
    var blockedApplications: Set<String> { Preferences.blockedApplications }

    func addToDictionary(_ word: String) {
        let updated = SettingsEditing.adding(word, to: Preferences.dictionary)
        guard updated != Preferences.dictionary else { return }
        Preferences.dictionary = updated
        reapplyUserDecisions()
    }

    func removeFromDictionary(_ words: Set<String>) {
        guard !words.isEmpty else { return }
        Preferences.dictionary = Preferences.dictionary.subtracting(words)
        reapplyUserDecisions()
    }

    func unmute(_ rules: Set<AlertPname>) {
        guard !rules.isEmpty else { return }
        Preferences.mutedRules = Preferences.mutedRules.subtracting(rules)
        for rule in rules { session.alertStore.unmute(rule: rule) }
        reapplyUserDecisions()
    }

    func blockApplication(_ identifier: String) {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SettingsEditing.isPlausibleBundleIdentifier(trimmed) else { return }
        Preferences.blockedApplications = Preferences.blockedApplications.union([trimmed])
        settingsRevision += 1
    }

    func unblockApplications(_ identifiers: Set<String>) {
        guard !identifiers.isEmpty else { return }
        Preferences.blockedApplications =
            Preferences.blockedApplications.subtracting(identifiers)
        settingsRevision += 1
    }

    func restoreBlockedDefaults() {
        Preferences.blockedApplications =
            SettingsEditing.restoringDefaults(in: Preferences.blockedApplications)
        settingsRevision += 1
    }

    /// Put the stored dictionary and mute list back into the live session and
    /// check again, so a word removed in Settings is underlined at once.
    private func reapplyUserDecisions() {
        session.alertStore.restore(dictionary: Preferences.dictionary,
                                   mutedRules: Preferences.mutedRules)
        settingsRevision += 1
        checkNow()
    }

    func newDocument() {
        startSession(with: "")
        persist()
    }

    /// Text put aside by `clearDocument`, and the task that will forget it.
    ///
    /// Clearing is one click away from a document someone may have been
    /// writing for an hour, and pushing text programmatically does not reach
    /// the text view's own undo stack — so without this, the toolbar would
    /// offer a destructive action with no way back.
    ///
    /// Thirty seconds, not ten: the first version used ten and the first test
    /// of it missed the window while the tester was still looking at the empty
    /// document working out what had happened. Someone who clears by mistake
    /// needs time to notice, not a reflex. Holding the text costs nothing —
    /// there is nothing to clear while the document is empty, so the button
    /// has no other job during the wait.
    private var clearedText: String?
    private var forgetClearedTask: Task<Void, Never>?

    /// Whether the last clear can still be taken back.
    @Published private(set) var canUndoClear = false

    func clearDocument() {
        guard !text.isEmpty else { return }
        let previous = text
        startSession(with: "")
        persist()

        clearedText = previous
        canUndoClear = true
        forgetClearedTask?.cancel()
        forgetClearedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.clearedText = nil
            self?.canUndoClear = false
        }
    }

    func undoClear() {
        guard let previous = clearedText else { return }
        forgetClearedTask?.cancel()
        clearedText = nil
        canUndoClear = false
        startSession(with: previous)
        persist()
    }

    /// Replace the whole document, e.g. with a selection arriving from a
    /// Service. Starts a fresh session because the incoming text has nothing
    /// to do with the previous revision history.
    func replaceDocument(with newText: String) {
        // Same reasoning as the correction Service: incoming text from
        // elsewhere should be detected, not forced into the dialect the window
        // happened to be left on.
        if dialect != .auto { dialect = .auto }
        startSession(with: newText)
        persist()
    }

    var alertCounts: [CardLayout.Outcome: Int] {
        session.alertStore.cardLayoutGroupCounts()
    }

    /// Opening document, in the interface's language so a French user is not
    /// greeted by an English sample.
    static func welcomeText(for locale: UILocale) -> String {
        locale == .french ? welcomeTextFrench : welcomeText
    }

    static let welcomeTextFrench = """
    rapport trimestriel

    En raison du fait que nous recevons un grand nombre de demandes chaque \
    semaine, l'equipe support a été débordée en octobre. Dans le but de \
    corriger cela, nous avons pris une décision: recruter deux personnes.

    Le probleme principal est vraiment le delai de traitement. Si j'aurais \
    su, nous aurions anticipé. Malgré que le systeme soit stable, la qualite \
    du service a baissé.

    Le ami de Marie a dit: "c'est tres bien". Il faut pallier à ce manque, \
    etc... Les resultats sont encourageants !
    """

    static let welcomeText = """
    teh quarterly update

    Due to the fact that we recieve a large number of requests each week, the \
    support team was overwhelmed in October. In order to fix this we have made \
    a decision to hire two more people.

    basically the backlog was reduced by the new process. The new process is \
    very good.

    A honest assessment: our documentation is seperate from the product. We \
    need manpower to fix it.

    they was told about the the issue last month.
    """
}
