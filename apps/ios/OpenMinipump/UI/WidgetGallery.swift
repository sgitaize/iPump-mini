// SPDX-License-Identifier: GPL-3.0-or-later
#if DEBUG
import SwiftUI
import WidgetKit

/// Debug only (launch argument `-widgetGallery`): renders the widget views at their real
/// sizes, so they can be checked in the simulator without adding them to the home screen.
struct WidgetGallery: View {
    @EnvironmentObject private var store: DataStore

    var body: some View {
        let snapshot = store.latest == nil ? WidgetSnapshot.placeholder : WidgetBridge.makeSnapshot(store: store)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                islandMatrix
                carPlay
                if let latest = snapshot.latest {
                    let state = GlucoseActivityAttributes.ContentState(
                        mgdl: latest.mgdl, trendRate: snapshot.trendRate, delta: snapshot.delta, date: latest.date, iob: snapshot.iob,
                        curve: GlucoseActivityAttributes.curve(from: snapshot.points, latest: latest.date))
                    LiveActivityView(state: state)
                        .padding(16)
                        .frame(width: 364)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 22))
                        .environment(\.colorScheme, .dark)
                    // Always-On (dimmed) variant
                    LiveActivityView(state: state)
                        .padding(16)
                        .frame(width: 364)
                        .background(.black, in: RoundedRectangle(cornerRadius: 22))
                        .environment(\.colorScheme, .dark)
                        .environment(\.isLuminanceReduced, true)
                }
                // Worst case for width: three arrows (and mmol/L if selected).
                ForEach([3.6, -2.4, 1.2], id: \.self) { rate in
                    let s = GlucoseActivityAttributes.ContentState(mgdl: 288, trendRate: rate, delta: 18, date: Date(), iob: 1.85, curve: nil)
                    let color = RangeColor.color(288, low: Prefs.low, high: Prefs.high, neutral: .primary)
                    HStack(spacing: 12) {
                        IslandCompactValue(state: s, unit: Prefs.unit, color: color)
                            .frame(maxWidth: 52, alignment: .leading)
                            .padding(8)
                            .background(.black, in: Capsule())
                        IslandValue(state: s, unit: Prefs.unit, color: color)
                            .frame(width: 110, alignment: .leading)
                            .padding(8)
                            .background(.black, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .environment(\.colorScheme, .dark)
                    LiveActivityView(state: s)
                        .padding(16)
                        .frame(width: 364)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 22))
                        .environment(\.colorScheme, .dark)
                }
                HStack(spacing: 16) {
                    tile(.systemSmall, snapshot, width: 170, height: 170)
                    VStack(spacing: 12) {
                        tile(.accessoryCircular, snapshot, width: 72, height: 72, lockScreen: true)
                        tile(.accessoryInline, snapshot, width: 170, height: 24, lockScreen: true)
                    }
                }
                tile(.accessoryRectangular, snapshot, width: 172, height: 76, lockScreen: true)
                tile(.systemMedium, snapshot, width: 364, height: 170)
                tile(.systemLarge, snapshot, width: 364, height: 382)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    /// Worst cases for the Dynamic Island: wide values, three arrows, mmol/L, at the widths iOS
    /// gives the compact leading region (alone ~52 pt, next to another activity down to ~30 pt)
    /// and the minimal circle (~25 pt content).
    private static let cases: [(Int, Double?, Int?)] = [(388, 3.6, 24), (40, -3.2, -18), (130, 0.2, 0), (99, nil, nil)]
    private static let widths: [CGFloat] = [52, 44, 36, 30]

    private var islandMatrix: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Dynamic Island compact / minimal").font(.caption.bold())
            ForEach(Self.cases.indices, id: \.self) { i in
                let (mgdl, rate, delta) = Self.cases[i]
                let s = GlucoseActivityAttributes.ContentState(mgdl: mgdl, trendRate: rate, delta: delta, date: Date(), iob: nil, curve: nil)
                let color = RangeColor.color(mgdl, low: Prefs.low, high: Prefs.high, neutral: .primary)
                HStack(spacing: 6) {
                    ForEach(Self.widths, id: \.self) { w in
                        IslandCompactValue(state: s, unit: Prefs.unit, color: color)
                            .frame(width: w, height: 24, alignment: .leading)
                            .clipped()
                            .border(.red.opacity(0.6), width: 0.5)
                    }
                    IslandCompactDelta(state: s, unit: Prefs.unit)
                        .frame(width: 40, height: 24, alignment: .trailing)
                        .clipped()
                        .border(.red.opacity(0.6), width: 0.5)
                    IslandMinimalValue(state: s, unit: Prefs.unit, color: color)
                        .frame(width: 25, height: 25)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.red.opacity(0.6), lineWidth: 0.5))
                }
                .padding(6)
                .background(.black, in: Capsule())
                .environment(\.colorScheme, .dark)
            }
        }
    }

    /// CarPlay small Live Activity (iOS 26), dark and light, at two plausible sizes.
    private var carPlay: some View {
        let latest = WidgetBridge.makeSnapshot(store: store)
        let curve = latest.latest.map { GlucoseActivityAttributes.curve(from: latest.points, latest: $0.date) }
        let fresh = GlucoseActivityAttributes.ContentState(mgdl: 388, trendRate: 3.6, delta: 24, date: Date(), iob: 2.35, curve: curve)
        let old = GlucoseActivityAttributes.ContentState(mgdl: 142, trendRate: -1.2, delta: -6, date: Date().addingTimeInterval(-25 * 60), iob: 0.4, curve: curve)
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "CarPlay (small)").font(.caption.bold())
            ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
                HStack(spacing: 8) {
                    ForEach([(CGFloat(170), CGFloat(84)), (220, 100)], id: \.0) { size in
                        LiveActivitySmallView(state: size.0 == 170 ? fresh : old)
                            .frame(width: size.0, height: size.1)
                            .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.95), in: RoundedRectangle(cornerRadius: 14))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .environment(\.colorScheme, scheme)
                    }
                }
            }
        }
    }

    private func tile(_ family: WidgetFamily, _ s: WidgetSnapshot, width: CGFloat, height: CGFloat, lockScreen: Bool = false) -> some View {
        GlucoseWidgetView(date: Date(), snapshot: s, familyOverride: family)
            .padding(lockScreen ? 0 : 14)
            .frame(width: width, height: height)
            .background(lockScreen ? AnyShapeStyle(.black.opacity(0.6)) : AnyShapeStyle(Color(.systemBackground)),
                        in: RoundedRectangle(cornerRadius: lockScreen ? 12 : 22))
            .environment(\.colorScheme, lockScreen ? .dark : .light)
    }
}
#endif
