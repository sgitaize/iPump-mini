// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Small teaser of the "Ausblick" page on the first page: when reservoir and battery run out
/// and the most important pattern, in one glance. Tapping it opens the full page.
struct OutlookPreview: View {
    @EnvironmentObject private var store: DataStore
    @AppStorage(Prefs.unitKey, store: Prefs.defaults) private var unitRaw = GlucoseUnit.mgdl.rawValue
    @AppStorage(Prefs.lowKey, store: Prefs.defaults) private var low = 70
    @AppStorage(Prefs.highKey, store: Prefs.defaults) private var high = 180
    let open: () -> Void

    var body: some View {
        let items = supplyItems
        let hint = PatternFinder(low: low, high: high)
            .hints(readings: store.readings, treatments: store.treatments, now: Date()).first
        if !items.isEmpty || hint != nil {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        ForEach(items, id: \.icon) { item in
                            Label {
                                Text(item.text).monospacedDigit()
                            } icon: {
                                Image(systemName: item.icon).foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                    if let hint {
                        Label {
                            Text(hint.message(unit: GlucoseUnit(rawValue: unitRaw) ?? .mgdl)).lineLimit(1)
                        } icon: {
                            Image(systemName: hint.kind == .low ? "arrow.down.circle.fill" : hint.kind == .high ? "arrow.up.circle.fill" : "chart.bar.fill")
                                .foregroundStyle(hint.kind == .low ? .red : hint.kind == .high ? .orange : .secondary)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Ausblick öffnen"))
            .accessibilityIdentifier("outlookPreview")
        }
    }

    private struct Item { let icon: String; let text: String }

    /// "bis Mi 18 Uhr" per supply; "lernt" while the forecast has too little data.
    private var supplyItems: [Item] {
        let s = store.snapshot
        let forecaster = SupplyForecaster()
        var items: [Item] = []
        func short(_ kind: SupplyKind) -> String? {
            switch forecaster.forecast(kind: kind, samples: store.supplyHistory, now: Date()) {
            case .noData: return nil
            case .learning: return L10n.tr("lernt")
            case let .ready(p):
                guard let e = p.empty else { return L10n.tr("> 30 T") }
                return p.current <= 0 ? L10n.tr("leer") : L10n.tr("bis %@", SupplyFormat.day(e.date))
            }
        }
        if s.status?.reservoirAttached == true, let t = short(.reservoir) { items.append(Item(icon: "drop.fill", text: t)) }
        if s.pumpBatteryPercent != nil, let t = short(.battery) { items.append(Item(icon: "battery.50", text: t)) }
        if items.count < 2, let end = s.sensorEnd, end > Date() {
            items.append(Item(icon: "dot.radiowaves.left.and.right", text: L10n.tr("bis %@", SupplyFormat.day(end))))
        }
        return items
    }
}
