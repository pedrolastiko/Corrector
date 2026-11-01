import SwiftUI
import AppKit
import CorrectorCore
import CorrectorEngine
import CorrectorAppCore

/// The settings window.
///
/// It exists because three preferences were already being written and could
/// only be read back with `defaults`: the personal dictionary, the muted
/// rules, and the applications the global shortcut refuses to act in. "Add to
/// dictionary" and "Mute rule" were one-way doors — a wrong click could not be
/// undone from inside the app.
///
/// `Preferences` stays the single store. Nothing here keeps its own copy of a
/// setting, so a change made in one tab is the same value the engine reads on
/// the next check.
struct SettingsView: View {
    @ObservedObject var model: DocumentModel
    @ObservedObject var updater: Updater
    @ObservedObject var login: LoginItemModel

    var body: some View {
        TabView {
            GeneralSettings(model: model, login: login)
                .tabItem { Label(model.strings.settingsGeneral, systemImage: "gearshape") }
            DictionarySettings(model: model)
                .tabItem { Label(model.strings.settingsDictionary, systemImage: "character.book.closed") }
            MutedRulesSettings(model: model)
                .tabItem { Label(model.strings.settingsRules, systemImage: "line.3.horizontal.decrease.circle") }
            ShortcutSettings(model: model)
                .tabItem { Label(model.strings.settingsShortcut, systemImage: "command") }
            UpdateSettings(model: model, updater: updater)
                .tabItem { Label(model.strings.settingsUpdates, systemImage: "arrow.down.circle") }
        }
            .frame(width: 520, height: 420)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var model: DocumentModel
    @ObservedObject var login: LoginItemModel

    var body: some View {
        Form {
            // Sections rather than Divider(): inside a grouped Form a divider
            // renders as an empty row, which reads as a missing control.
            Section {
            Picker(model.strings.interfaceLanguage, selection: $model.uiLocale) {
                ForEach(UILocale.allCases) { Text($0.displayName).tag($0) }
            }
            Picker(model.strings.dialect, selection: $model.dialect) {
                Text(model.strings.detectAutomatically).tag(Dialect.auto)
                Divider()
                ForEach(Dialect.allCases.filter { $0.language == .english && $0 != .auto },
                        id: \.self) { Text($0.displayName).tag($0) }
                Divider()
                ForEach(Dialect.allCases.filter { $0.language == .french },
                        id: \.self) { Text($0.displayName).tag($0) }
            }
            }

            Section {
            switch login.state {
            case .on, .off:
                Toggle(model.strings.openAtLogin,
                       isOn: Binding(get: { LoginItem.isOn(login.state) },
                                     set: { _ in login.activate() }))
            case .needsApproval:
                Button(model.strings.loginNeedsApproval) { login.activate() }
            case .unavailable:
                Text(model.strings.loginUnavailable).foregroundStyle(.secondary)
            }
            }
        }
            .formStyle(.grouped)
                .onAppear { login.refresh() }
    }
}

// MARK: - Dictionary

private struct DictionarySettings: View {
    @ObservedObject var model: DocumentModel
    @State private var draft = ""
    @State private var selection: Set<String> = []

    private var words: [String] { SettingsEditing.sorted(model.dictionaryWords) }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.md) {
            if words.isEmpty {
                EmptyHint(text: model.strings.emptyDictionary)
            } else {
                List(words, id: \.self, selection: $selection) { Text($0) }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
            }
            HStack {
                TextField(model.strings.addWord, text: $draft)
                    .onSubmit(add)
                Button(model.strings.addToList, action: add)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button(model.strings.remove) {
                    model.removeFromDictionary(selection)
                    selection = []
                }
                    .disabled(selection.isEmpty)
            }
        }
            .padding(Metric.lg)
    }

    private func add() {
        model.addToDictionary(draft)
        draft = ""
    }
}

// MARK: - Muted rules

private struct MutedRulesSettings: View {
    @ObservedObject var model: DocumentModel
    @State private var selection: Set<AlertPname> = []

    private var rules: [AlertPname] {
        model.mutedRules.sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.md) {
            if rules.isEmpty {
                EmptyHint(text: model.strings.emptyMutedRules)
            } else {
                List(rules, id: \.self, selection: $selection) { Text($0.rawValue) }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
            }
            HStack {
                Spacer()
                Button(model.strings.unmute) {
                    model.unmute(selection)
                    selection = []
                }
                    .disabled(selection.isEmpty)
            }
        }
            .padding(Metric.lg)
    }
}

// MARK: - Shortcut

private struct ShortcutSettings: View {
    @ObservedObject var model: DocumentModel
    @State private var draft = ""
    @State private var selection: Set<String> = []
    @State private var problem: String?

    private var blocked: [String] { SettingsEditing.sorted(model.blockedApplications) }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.md) {
            Text(model.strings.blockedApplications).font(.headline)
            Text(model.strings.blockedApplicationsHelp)
                .font(.caption)
                    .foregroundStyle(.secondary)

            List(blocked, id: \.self, selection: $selection) { identifier in
                HStack {
                    Text(identifier)
                    if SettingsEditing.isShippedProtection(identifier) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.secondary)
                                .help(model.strings.shippedProtectionWarning)
                    }
                }
            }
                .listStyle(.bordered(alternatesRowBackgrounds: true))

            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }

            HStack {
                TextField(model.strings.addApplication, text: $draft)
                    .onSubmit(add)
                Button(model.strings.addToList, action: add)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button(model.strings.remove) {
                    model.unblockApplications(selection)
                    selection = []
                }
                    .disabled(selection.isEmpty)
                Button(model.strings.restoreDefaults) { model.restoreBlockedDefaults() }
            }
        }
            .padding(Metric.lg)
    }

    private func add() {
        guard SettingsEditing.isPlausibleBundleIdentifier(draft) else {
            problem = model.strings.invalidBundleIdentifier
            return
        }
        problem = nil
        model.blockApplication(draft)
        draft = ""
    }
}

// MARK: - Updates

private struct UpdateSettings: View {
    @ObservedObject var model: DocumentModel
    @ObservedObject var updater: Updater

    var body: some View {
        Form {
            Section {
            if updater.isConfigured {
                Toggle(model.strings.automaticUpdates, isOn: $updater.checksAutomatically)
                Button(model.strings.checkForUpdates) { updater.checkForUpdates() }
                    .disabled(!updater.canCheck)
            } else {
                // Honest rather than hopeful: a build with no feed cannot
                // check, and a greyed-out button with no reason beside it is
                // the kind of silence this project keeps trying to remove.
                Text(model.strings.updatesNotConfigured)
                    .foregroundStyle(.secondary)
            }
            }
            Section {
                LabeledContent("Corrector", value: Release.display)
            }
        }
            .formStyle(.grouped)
    }
}

// MARK: -

private struct EmptyHint: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.callout)
                    .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
            Spacer()
        }
            .frame(maxWidth: .infinity)
    }
}
