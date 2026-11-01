import Foundation
import CorrectorDelta

/// What changed in the store after an update — the shape the UI needs to
/// animate cards in, out and in place.
public struct AlertDiff: Equatable, Sendable {
    public var added: [Alert] = []
    public var updated: [Alert] = []
    public var removed: [Int] = []
    public var isEmpty: Bool { added.isEmpty && updated.isEmpty && removed.isEmpty }
}

/// Holds the live alert set for a document and keeps it anchored as the text
/// changes.
///
/// The update-versus-replacement distinction, together with rebasing alerts
/// through each changeset, is what stops cards flickering and jumping while
/// someone types. It is the hardest behaviour in a checker of this kind to get
/// right, and the easiest to get wrong without noticing.
public final class AlertStore {
    public private(set) var alerts: [Alert] = []
    public private(set) var revision: Int = 0

    /// Rules the user has muted, and words added to the personal dictionary.
    public private(set) var mutedRules: Set<AlertPname> = []
    public private(set) var dictionary: Set<String> = []

    public private(set) var selectedID: Int?

    public init() {}

    public var visibleAlerts: [Alert] {
        alerts
            .filter { !$0.hidden && !$0.muted }
                .sorted { $0.isPriorityHigherThan($1) }
    }

    public func alert(id: Int) -> Alert? { alerts.first { $0.id == id } }

    // MARK: - Rebasing

    /// Move every held alert onto `newRevision` through `delta`, dropping any
    /// whose span the edit destroyed.
    @discardableResult
    public func rebase(through delta: Delta, newRevision: Int) -> AlertDiff {
        guard !delta.isEmpty else { revision = newRevision; return AlertDiff() }
        var diff = AlertDiff()
        var survivors: [Alert] = []

        for alert in alerts {
            if let moved = alert.rebased(through: delta, newRevision: newRevision) {
                if moved.begin != alert.begin || moved.end != alert.end {
                    diff.updated.append(moved)
                }
                survivors.append(moved)
            } else {
                diff.removed.append(alert.id)
            }
        }
        alerts = survivors
        revision = newRevision
        if let selected = selectedID, !alerts.contains(where: { $0.id == selected }) {
            selectedID = nil
        }
        return diff
    }

    // MARK: - Applying a check result

    /// Merge a freshly computed alert set.
    ///
    /// An incoming alert that matches one already held updates it **in place**,
    /// preserving the card's position and the user's selection; everything else
    /// is added or removed.
    @discardableResult
    public func apply(incoming: [Alert], revision newRevision: Int) -> AlertDiff {
        var diff = AlertDiff()
        var next: [Alert] = []
        var matchedExisting = Set<Int>()

        for var candidate in incoming {
            if mutedRules.contains(candidate.pname) { candidate.muted = true }
            if candidate.pname == .misspelled,
               dictionary.contains(candidate.highlightText.lowercased()) {
                continue
            }

            if let existing = alerts.first(where: { $0.isUpdated(by: candidate) && !matchedExisting.contains($0.id) }) {
                matchedExisting.insert(existing.id)
                candidate.id = existing.id          // keep identity so the card survives
                candidate.rev = newRevision
                if candidate != existing { diff.updated.append(candidate) }
                next.append(candidate)
            } else {
                candidate.rev = newRevision
                diff.added.append(candidate)
                next.append(candidate)
            }
        }

        for existing in alerts where !matchedExisting.contains(existing.id) {
            diff.removed.append(existing.id)
        }

        alerts = next
        revision = newRevision
        if let selected = selectedID, !alerts.contains(where: { $0.id == selected }) {
            selectedID = nil
        }
        return diff
    }

    // MARK: - User actions

    public func select(id: Int?) { selectedID = id }

    @discardableResult
    public func remove(id: Int) -> Bool {
        let before = alerts.count
        alerts.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        return alerts.count != before
    }

    public func mute(rule: AlertPname) {
        mutedRules.insert(rule)
        for index in alerts.indices where alerts[index].pname == rule {
            alerts[index].muted = true
        }
    }

    public func unmute(rule: AlertPname) {
        mutedRules.remove(rule)
        for index in alerts.indices where alerts[index].pname == rule {
            alerts[index].muted = false
        }
    }

    /// Reinstate a previously saved dictionary and mute list.
    ///
    /// Both are user decisions that must outlive the process: a word added to
    /// the dictionary should stay added, and a muted rule should stay muted.
    public func restore(dictionary words: Set<String>, mutedRules rules: Set<AlertPname>) {
        dictionary = Set(words.map { $0.lowercased() })
        mutedRules = rules
        for index in alerts.indices where mutedRules.contains(alerts[index].pname) {
            alerts[index].muted = true
        }
        alerts.removeAll {
            $0.pname == .misspelled && dictionary.contains($0.highlightText.lowercased())
        }
    }

    public func addToDictionary(_ word: String) {
        dictionary.insert(word.lowercased())
        alerts.removeAll { $0.pname == .misspelled
                        && $0.highlightText.lowercased() == word.lowercased() }
    }

    /// Card counts per outcome, for the summary header.
    ///
    /// Per-category counts for the summary header.
    public func cardLayoutGroupCounts() -> [CardLayout.Outcome: Int] {
        visibleAlerts.reduce(into: [:]) { counts, alert in
            counts[alert.cardLayout.outcome, default: 0] += 1
        }
    }
}
