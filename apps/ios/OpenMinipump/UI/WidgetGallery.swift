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
