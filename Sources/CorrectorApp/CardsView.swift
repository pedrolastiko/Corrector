import SwiftUI
import CorrectorCore
import CorrectorAppCore

/// The suggestion list.
///
/// A compact row that expands into a card carrying the explanation, the
/// alternatives and an action row computed from the `AlertActions` bitmask
/// rather than drawn as fixed buttons. Compact by default, because twenty open
/// cards is not a list anyone reads.
struct CardsView: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        if model.alerts.isEmpty {
            ContentUnavailableLikeView(strings: model.strings)
        } else {
            ScrollView {
                LazyVStack(spacing: Metric.md) {
                    ForEach(model.alerts) { alert in
                        AlertCard(alert: alert,
                                  isExpanded: model.expandedAlertID == alert.id,
                                  isSelected: model.selectedAlertID == alert.id,
                                  model: model)
                    }
                }
                    .padding(Metric.lg)
            }
        }
    }
}

private struct ContentUnavailableLikeView: View {
    let strings: Strings
    var body: some View {
        VStack(spacing: Metric.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30))
                    .foregroundStyle(Theme.Palette.teal.swiftUIColor)
            Text(strings.noSuggestions).font(.headline)
            Text(strings.readsWell)
                .font(.caption).foregroundStyle(.secondary)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AlertCard: View {
    let alert: Alert
    let isExpanded: Bool
    let isSelected: Bool
    @ObservedObject var model: DocumentModel

    private var tint: Color { alert.cardLayout.outcome.tint }
    private var strings: Strings { model.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.md) {
            header
            if isExpanded { expandedBody }
        }
            .padding(Metric.lg)
                .background(
            RoundedRectangle(cornerRadius: Metric.radiusMedium)
                .fill(isSelected ? tint.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
            .overlay(
            RoundedRectangle(cornerRadius: Metric.radiusMedium)
                .strokeBorder(isSelected ? tint.opacity(0.55) : .clear, lineWidth: 1.5)
        )
            .overlay(alignment: .leading) {
            Rectangle().fill(tint)
                .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: Metric.radiusSmall))
        }
            .contentShape(Rectangle())
                .onTapGesture { model.toggleExpanded(alert.id) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Metric.md) {
            Image(systemName: alert.cardLayout.outcome.symbolName)
                .font(.caption).foregroundStyle(tint).frame(width: 16)

            VStack(alignment: .leading, spacing: Metric.xs) {
                Text(alert.title).font(.subheadline).fontWeight(.medium)

                // Mini card: the primary replacement, shown inline
                //.
                if let replacement = alert.replacements.first {
                    HStack(spacing: Metric.sm) {
                        Text(alert.highlightText)
                            .strikethrough()
                                .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Text(replacement.isEmpty ? strings.deleteReplacement : replacement)
                            .foregroundStyle(tint).fontWeight(.medium)
                    }
                        .font(.callout)
                } else if !alert.details.isEmpty {
                    Text(alert.details).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)

            if alert.actions.contains(.accept) {
                // Standard control size rather than.small: this is the one
                // action on the card that gets used repeatedly, so it should
                // be the easiest thing on it to hit.
                Button(strings.accept) { model.accept(alert) }
                    .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                            .tint(tint)
                                .font(.callout.weight(.medium))
                                    .fixedSize()
            }
        }
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: Metric.md) {
            Divider()

            if !alert.details.isEmpty, !alert.replacements.isEmpty {
                Text(alert.details).font(.caption)
            }
            if !alert.explanation.isEmpty {
                Text(alert.explanation)
                    .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(alert.examples, id: \.self) { example in
                Text("e.g. \(example)")
                    .font(.caption2).foregroundStyle(.tertiary).italic()
            }
            if alert.replacements.count > 1 {
                Text(strings.alsoSuggestions + ": " + alert.replacements.dropFirst()
                    .map { $0.isEmpty ? strings.deleteReplacement : $0 }
                        .joined(separator: ", "))
                            .font(.caption2).foregroundStyle(.secondary)
            }

            // The action row is a computed bitmask, not a fixed layout
            //.
            HStack(spacing: Metric.md) {
                if alert.actions.contains(.dismiss) {
                    Button(strings.dismiss) { model.dismiss(alert) }
                }
                if alert.actions.contains(.mute) {
                    Button(strings.muteRule) { model.muteRule(of: alert) }
                }
                if alert.actions.contains(.addToDictionary) {
                    Button(strings.addToDictionary) { model.addToDictionary(alert) }
                }
                Spacer()
                Text(alert.pname.rawValue)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
                .buttonStyle(.link)
                    .font(.caption)
        }
    }
}
